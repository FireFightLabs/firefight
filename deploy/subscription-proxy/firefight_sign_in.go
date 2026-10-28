// Firefight's addition to the CLIProxyAPI server, built into its own cmd/server package (see the Dockerfile).
//
// Firefight names each sign-in it starts: the start request carries the sign-in's id and the workspace it is for. The
// proxy hands that request to its post-auth hook with every credential a sign-in saves, background goroutines
// included, so the hook stamps the credential with the workspace's prefix and the sign-in's id before it is saved.
// Firefight then asks which credential the sign-in made (GET /firefight/sign-ins/:id) rather than guessing.
//
// A login is one account at its provider, whatever file name the proxy gives it (Kimi's carry the time, Codex's the
// plan). The same login already connected to another workspace is refused, and signed in again in its own workspace
// it replaces its credential rather than adding a second. The check and the save are not one step in the proxy, so a
// login being signed in is held for its workspace until its save has landed. The hold is in this process, so the
// proxy runs as exactly one instance. A credential saved with no valid id is refused.
package main

import (
	"context"
	"crypto/subtle"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"os"
	"regexp"
	"strings"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/router-for-me/CLIProxyAPI/v8/internal/api"
	sdkAuth "github.com/router-for-me/CLIProxyAPI/v8/sdk/auth"
	coreauth "github.com/router-for-me/CLIProxyAPI/v8/sdk/cliproxy/auth"
)

const (
	firefightSignInParam    = "firefight_sign_in"
	firefightWorkspaceParam = "firefight_workspace"
	// Kept on the credential and shown in the proxy's credential list.
	firefightNoteKey         = "note"
	firefightSignInKey       = "firefight_sign_in"
	firefightPrefixKey       = "prefix"
	firefightRefusedTaken    = "taken"
	firefightRefusedUnnamed  = "unnamed"
	firefightRefusalsKeptFor = 24 * time.Hour
	// Longer than any save takes, after which the saved credential itself says whose the login is.
	firefightHoldFor = 2 * time.Minute
)

// What names the login at its provider, most specific first, in the credential or in the token it was given.
var firefightIdentityKeys = []string{"account_id", "sub", "user_id", "uid", "account_uuid", "email"}

var firefightID = regexp.MustCompile(`^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$`)

type firefightRefusal struct {
	reason string
	at     time.Time
}

// A login being saved, for its workspace, under the name it is saved as.
type firefightHold struct {
	workspace string
	id        string
	fileName  string
	until     time.Time
}

var (
	firefightRefusals sync.Map
	firefightHoldsMu  sync.Mutex
	firefightHolds    = map[string]firefightHold{}
)

func firefightServerOptions() []api.ServerOption {
	return []api.ServerOption{
		api.WithPostAuthHook(firefightStampSignIn),
		api.WithEngineConfigurator(func(engine *gin.Engine) {
			engine.GET("/firefight/sign-ins/:id", firefightSignInResult)
		}),
	}
}

func firefightStampSignIn(ctx context.Context, record *coreauth.Auth) error {
	if record == nil {
		return errors.New("firefight: no credential to save")
	}
	info := coreauth.GetRequestInfo(ctx)
	if info == nil {
		return errors.New("firefight: a sign-in Firefight did not start is not saved")
	}
	signIn := strings.TrimSpace(info.Query.Get(firefightSignInParam))
	workspace := strings.TrimSpace(info.Query.Get(firefightWorkspaceParam))
	if !firefightID.MatchString(signIn) || !firefightID.MatchString(workspace) {
		if firefightID.MatchString(signIn) {
			firefightRefuse(signIn, firefightRefusedUnnamed)
		}
		return errors.New("firefight: a sign-in Firefight did not name is not saved")
	}

	// The proxy merged the credential saved under the same file name into this one before the hook.
	if merged := firefightPrefixOf(record); merged != "" && merged != workspace {
		firefightRefuse(signIn, firefightRefusedTaken)
		return errors.New("firefight: this account is already connected to another workspace")
	}

	firefightHoldsMu.Lock()
	defer firefightHoldsMu.Unlock()
	login := firefightLogin(record.Provider, firefightIdentity(record.Metadata, record.Storage))
	if login != "" {
		now := time.Now()
		for key, hold := range firefightHolds {
			if now.After(hold.until) {
				delete(firefightHolds, key)
			}
		}
		if hold, held := firefightHolds[login]; held && hold.workspace != workspace {
			firefightRefuse(signIn, firefightRefusedTaken)
			return errors.New("firefight: this account is being connected to another workspace")
		}
		same, err := firefightSavedLogin(ctx, record.Provider, login)
		if err != nil {
			return fmt.Errorf("firefight: could not read the saved credentials: %w", err)
		}
		if same != nil {
			if owner := firefightPrefixOf(same); owner != workspace {
				firefightRefuse(signIn, firefightRefusedTaken)
				return errors.New("firefight: this account is already connected to another workspace")
			}
			firefightReplace(record, same)
		} else if hold, held := firefightHolds[login]; held {
			// Signed in twice at once in one workspace, both go under one name.
			record.ID = hold.id
			record.FileName = hold.fileName
		}
		firefightHolds[login] = firefightHold{workspace: workspace, id: record.ID, fileName: record.FileName, until: now.Add(firefightHoldFor)}
	}

	record.Prefix = workspace
	if record.Metadata == nil {
		record.Metadata = make(map[string]any)
	}
	record.Metadata[firefightPrefixKey] = workspace
	record.Metadata[firefightSignInKey] = signIn
	record.Metadata[firefightNoteKey] = signIn
	if record.Attributes == nil {
		record.Attributes = make(map[string]string)
	}
	record.Attributes[firefightNoteKey] = signIn
	if setter, ok := record.Storage.(interface{ SetMetadata(map[string]any) }); ok {
		setter.SetMetadata(record.Metadata)
	}
	return nil
}

// The login signed in again in its own workspace keeps its credential: the new tokens are saved over it, under its
// name, with what was set on it (its priority, whether it is on) kept.
func firefightReplace(record, same *coreauth.Auth) {
	record.ID = same.ID
	record.FileName = same.FileName
	if path := strings.TrimSpace(same.Attributes[coreauth.AttributePath]); path != "" {
		if record.Attributes == nil {
			record.Attributes = make(map[string]string)
		}
		record.Attributes[coreauth.AttributePath] = path
	}
	coreauth.MergeExistingAuthMetadata(record, same.Metadata)
}

func firefightSavedLogin(ctx context.Context, provider, login string) (*coreauth.Auth, error) {
	saved, err := sdkAuth.GetTokenStore().List(ctx)
	if err != nil {
		return nil, err
	}
	for _, auth := range saved {
		if auth != nil && firefightLogin(auth.Provider, firefightIdentity(auth.Metadata, nil)) == login {
			return auth, nil
		}
	}
	return nil, nil
}

func firefightLogin(provider, identity string) string {
	if identity == "" {
		return ""
	}
	return strings.ToLower(strings.TrimSpace(provider)) + "|" + identity
}

// Read from the credential, its storage, and the claims of the tokens it holds, never from its file name.
func firefightIdentity(metadata map[string]any, storage any) string {
	fields := map[string]any{}
	if storage != nil {
		if raw, err := json.Marshal(storage); err == nil {
			_ = json.Unmarshal(raw, &fields)
		}
	}
	for key, value := range metadata {
		fields[key] = value
	}
	if identity := firefightIdentityIn(fields); identity != "" {
		return identity
	}
	for _, token := range []string{"id_token", "access_token"} {
		if raw, ok := fields[token].(string); ok {
			if identity := firefightIdentityIn(firefightClaims(raw)); identity != "" {
				return identity
			}
		}
	}
	return ""
}

func firefightIdentityIn(fields map[string]any) string {
	for _, key := range firefightIdentityKeys {
		switch value := fields[key].(type) {
		case string:
			if trimmed := strings.ToLower(strings.TrimSpace(value)); trimmed != "" {
				return key + ":" + trimmed
			}
		case float64:
			return fmt.Sprintf("%s:%.0f", key, value)
		}
	}
	return ""
}

// The claims of a JSON web token, or nothing when the token is not one.
func firefightClaims(token string) map[string]any {
	parts := strings.Split(token, ".")
	if len(parts) != 3 {
		return nil
	}
	payload, err := base64.RawURLEncoding.DecodeString(strings.TrimRight(parts[1], "="))
	if err != nil {
		return nil
	}
	claims := map[string]any{}
	if json.Unmarshal(payload, &claims) != nil {
		return nil
	}
	return claims
}

func firefightPrefixOf(auth *coreauth.Auth) string {
	if auth.Metadata != nil {
		if prefix, ok := auth.Metadata[firefightPrefixKey].(string); ok && strings.TrimSpace(prefix) != "" {
			return strings.TrimSpace(prefix)
		}
	}
	return strings.TrimSpace(auth.Prefix)
}

func firefightRefuse(signIn, reason string) {
	now := time.Now()
	firefightRefusals.Store(signIn, firefightRefusal{reason: reason, at: now})
	firefightRefusals.Range(func(key, value any) bool {
		if refusal, ok := value.(firefightRefusal); ok && now.Sub(refusal.at) > firefightRefusalsKeptFor {
			firefightRefusals.Delete(key)
		}
		return true
	})
}

// What became of a sign-in, for Firefight alone, with the management key: the credential it made and the workspace
// that credential serves, or why it was refused.
func firefightSignInResult(c *gin.Context) {
	key := strings.TrimSpace(os.Getenv("MANAGEMENT_PASSWORD"))
	given := strings.TrimSpace(strings.TrimPrefix(c.GetHeader("Authorization"), "Bearer "))
	if key == "" || subtle.ConstantTimeCompare([]byte(key), []byte(given)) != 1 {
		c.AbortWithStatus(http.StatusNotFound)
		return
	}
	id := c.Param("id")
	result := gin.H{"refused": "", "credential": "", "workspace": ""}
	if value, ok := firefightRefusals.Load(id); ok {
		result["refused"] = value.(firefightRefusal).reason
	}
	saved, err := sdkAuth.GetTokenStore().List(c.Request.Context())
	if err != nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "the saved credentials could not be read"})
		return
	}
	for _, auth := range saved {
		if auth == nil || auth.Metadata == nil {
			continue
		}
		if stamped, _ := auth.Metadata[firefightSignInKey].(string); stamped == id {
			result["credential"] = auth.FileName
			result["workspace"] = firefightPrefixOf(auth)
			break
		}
	}
	c.JSON(http.StatusOK, result)
}
