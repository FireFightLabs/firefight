// Firefight's addition to the CLIProxyAPI server, built into its own cmd/server package (see the Dockerfile).
//
// Firefight names each sign-in it starts: the start request carries the sign-in's id and the workspace it is for. The
// proxy hands that request to its post-auth hook with every credential a sign-in saves, background goroutines
// included, so the hook stamps the credential with the workspace's prefix and the sign-in's id before it is saved.
// Firefight then finds the credential by that id rather than guessing. A credential saved with no valid id, or one
// that would overwrite another workspace's credential (the same login signed in elsewhere), is refused, and why is
// kept for Firefight to ask.
package main

import (
	"context"
	"crypto/subtle"
	"errors"
	"net/http"
	"os"
	"regexp"
	"strings"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/router-for-me/CLIProxyAPI/v8/internal/api"
	coreauth "github.com/router-for-me/CLIProxyAPI/v8/sdk/cliproxy/auth"
)

const (
	firefightSignInParam    = "firefight_sign_in"
	firefightWorkspaceParam = "firefight_workspace"
	// Kept on the credential and shown in the proxy's credential list, where Firefight reads it.
	firefightNoteKey         = "note"
	firefightSignInKey       = "firefight_sign_in"
	firefightRefusedTaken    = "taken"
	firefightRefusedUnnamed  = "unnamed"
	firefightRefusalsKeptFor = 24 * time.Hour
)

var firefightID = regexp.MustCompile(`^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$`)

type firefightRefusal struct {
	reason string
	at     time.Time
}

var firefightRefusals sync.Map

func firefightServerOptions() []api.ServerOption {
	return []api.ServerOption{
		api.WithPostAuthHook(firefightStampSignIn),
		api.WithEngineConfigurator(func(engine *gin.Engine) {
			engine.GET("/firefight/sign-ins/:id", firefightSignInRefusal)
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

	// The proxy merges the credential already saved for the same login into this one before the hook, so a prefix
	// here is the workspace that login is connected to.
	existing := strings.TrimSpace(record.Prefix)
	if record.Metadata != nil {
		if prefix, ok := record.Metadata["prefix"].(string); ok && strings.TrimSpace(prefix) != "" {
			existing = strings.TrimSpace(prefix)
		}
	}
	if existing != "" && existing != workspace {
		firefightRefuse(signIn, firefightRefusedTaken)
		return errors.New("firefight: this account is already connected to another workspace")
	}

	record.Prefix = workspace
	if record.Metadata == nil {
		record.Metadata = make(map[string]any)
	}
	record.Metadata["prefix"] = workspace
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

// Why the hook refused a sign-in's credential, for Firefight alone, with the management key.
func firefightSignInRefusal(c *gin.Context) {
	key := strings.TrimSpace(os.Getenv("MANAGEMENT_PASSWORD"))
	given := strings.TrimSpace(strings.TrimPrefix(c.GetHeader("Authorization"), "Bearer "))
	if key == "" || subtle.ConstantTimeCompare([]byte(key), []byte(given)) != 1 {
		c.AbortWithStatus(http.StatusNotFound)
		return
	}
	refused := ""
	if value, ok := firefightRefusals.Load(c.Param("id")); ok {
		refused = value.(firefightRefusal).reason
	}
	c.JSON(http.StatusOK, gin.H{"refused": refused})
}
