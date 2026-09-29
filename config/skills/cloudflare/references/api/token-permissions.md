---
description: Review available Cloudflare API token permissions for user, account, and zone resources.
title: API token permissions
image: https://developers.cloudflare.com/fundamentals/api/reference/permissions/og.png?v=d5142d1f6e167ad8
---

[Skip to content](#main-content)

> Documentation Index  
> Fetch the complete documentation index at: https://developers.cloudflare.com/fundamentals/llms.txt  
> Use this file to discover all available pages before exploring further.

# API token permissions

Last updated Sep 16, 2026|Copy as Markdown| [View as Markdown](https://developers.cloudflare.com/fundamentals/api/reference/permissions/index.md)| [Agent setup](https://developers.cloudflare.com/agent-setup/)

Permissions are segmented into three categories based on resource:

- Zone permissions
- Account permissions
- User permissions

Each category contains permission groups related to those resources. DNS permissions belong to the Zone category, while Billing permissions belong to the Account category. Below is a list of the available token permissions.

To obtain an updated list of token permissions, including the permission ID and the scope of each permission, use the [List permission groups](https://developers.cloudflare.com/api/resources/user/subresources/tokens/subresources/permission_groups/methods/list/) endpoint.

## User permissions

The applicable scope of user permissions is `com.cloudflare.api.user`.

| Name | Description |
| --- | --- |
| API Tokens Read | Grants read access to user's [API tokens](https://developers.cloudflare.com/fundamentals/api/reference/permissions/). |
| API Tokens Edit | Grants write access to user's [API tokens](https://developers.cloudflare.com/fundamentals/api/reference/permissions/). |
| Memberships Read | Grants read access to a user's [account memberships](https://developers.cloudflare.com/fundamentals/manage-members/manage/). |
| Memberships Edit | Grants write access to a user's [account memberships](https://developers.cloudflare.com/fundamentals/manage-members/manage/). |
| User Details Read | Grants read access to user details. |
| User Details Edit | Grants write access to user details. |

| Name | Description |
| --- | --- |
| API Tokens Read | Grants read access to user's [API tokens](https://developers.cloudflare.com/fundamentals/api/reference/permissions/). |
| API Tokens Write | Grants write access to user's [API tokens](https://developers.cloudflare.com/fundamentals/api/reference/permissions/). |
| Memberships Read | Grants read access to a user's [account memberships](https://developers.cloudflare.com/fundamentals/manage-members/manage/). |
| Memberships Write | Grants write access to a user's [account memberships](https://developers.cloudflare.com/fundamentals/manage-members/manage/). |
| User Details Read | Grants read access to user details. |
| User Details Write | Grants write access to user details. |

## Account permissions

The applicable scope of account permissions is `com.cloudflare.api.account`.

Note

The `AI Gateway Read`, `Run`, and `Edit` permissions are account-scoped only — they cannot be restricted to a single gateway. For details, refer to [Authenticated Gateway](https://developers.cloudflare.com/ai-gateway/configuration/authentication/).

| Name | Description |
| --- | --- |
| Access: Apps and Policies Read | Grants read access to Cloudflare Access [applications](https://developers.cloudflare.com/cloudflare-one/access-controls/applications/) and [policies](https://developers.cloudflare.com/cloudflare-one/access-controls/policies/). |
| Access: Apps and Policies Revoke | Grants ability to revoke [Cloudflare Access application tokens](https://developers.cloudflare.com/cloudflare-one/access-controls/access-settings/session-management/) |
| Access: Apps and Policies Edit | Grants write access to Cloudflare Access [applications](https://developers.cloudflare.com/cloudflare-one/access-controls/applications/) and [policies](https://developers.cloudflare.com/cloudflare-one/access-controls/policies/). |
| Access: Apps Read | Grants read access to [Cloudflare Access applications](https://developers.cloudflare.com/cloudflare-one/access-controls/applications/). |
| Access: Apps Revoke | Grants ability to revoke [Cloudflare Access application tokens](https://developers.cloudflare.com/cloudflare-one/access-controls/access-settings/session-management/). |
| Access: Apps Edit | Grants write access to [Cloudflare Access applications](https://developers.cloudflare.com/cloudflare-one/access-controls/applications/). |
| Access: Audit Logs Read | Grants read access to [Cloudflare Access authentication logs](https://developers.cloudflare.com/cloudflare-one/insights/logs/dashboard-logs/access-authentication-logs/). |
| Access: Custom Pages Read | Grants read access to [Cloudflare Access custom block pages](https://developers.cloudflare.com/cloudflare-one/reusable-components/custom-pages/access-block-page/). |
| Access: Custom Pages Edit | Grants write access to [Cloudflare Access custom block pages](https://developers.cloudflare.com/cloudflare-one/reusable-components/custom-pages/access-block-page/). |
| Access: Device Posture Read | Grants read access to [Cloudflare Access device posture](https://developers.cloudflare.com/cloudflare-one/reusable-components/posture-checks/). |
| Access: Device Posture Edit | Grants write access to [Cloudflare Access device posture](https://developers.cloudflare.com/cloudflare-one/reusable-components/posture-checks/). |
| Access: Groups Read | Grants read access to [Cloudflare Access rule groups](https://developers.cloudflare.com/cloudflare-one/access-controls/policies/groups/). |
| Access: Groups Edit | Grants write access to [Cloudflare Access rule groups](https://developers.cloudflare.com/cloudflare-one/access-controls/policies/groups/). |
| Access: Identity Providers Read | Grants read access to [Cloudflare One identity providers](https://developers.cloudflare.com/cloudflare-one/integrations/identity-providers/). |
| Access: Identity Providers Edit | Grants write access to [Cloudflare One identity providers](https://developers.cloudflare.com/cloudflare-one/integrations/identity-providers/). |
| Access: Keys Read | Grants read access to [Cloudflare Access signing keys](https://developers.cloudflare.com/cloudflare-one/access-controls/applications/http-apps/authorization-cookie/validating-json/). |
| Access: Keys Edit | Grants ability to rotate [Cloudflare Access signing keys](https://developers.cloudflare.com/cloudflare-one/access-controls/applications/http-apps/authorization-cookie/validating-json/). |
| Access: Mutual TLS Certificates Read | Grants read access to [Cloudflare Access mTLS certificates](https://developers.cloudflare.com/cloudflare-one/access-controls/service-credentials/mutual-tls-authentication/). |
| Access: Mutual TLS Certificates Edit | Grants write access to [Cloudflare Access mTLS certificates](https://developers.cloudflare.com/cloudflare-one/access-controls/service-credentials/mutual-tls-authentication/). |
| Access: Organizations Read | Grants read access to [Zero Trust Organization settings](https://developers.cloudflare.com/api/resources/zero_trust/subresources/organizations/methods/list/). |
| Access: Organizations Revoke | Grants ability to [revoke user sessions](https://developers.cloudflare.com/cloudflare-one/access-controls/access-settings/session-management/#revoke-user-sessions) in a Zero Trust organization. |
| Access: Organizations Edit | Grants write access to [Zero Trust Organization settings](https://developers.cloudflare.com/api/resources/zero_trust/subresources/organizations/methods/list/). |
| Access: Organizations, Identity Providers, and Groups Read | Grants read access to [Zero Trust Organization settings](https://developers.cloudflare.com/api/resources/zero_trust/subresources/organizations/methods/list/), [Cloudflare One identity providers](https://developers.cloudflare.com/cloudflare-one/integrations/identity-providers/), and [Cloudflare Access rule groups](https://developers.cloudflare.com/cloudflare-one/access-controls/policies/groups/). |
| Access: Organizations, Identity Providers, and Groups Revoke | Grants ability to [revoke users](https://developers.cloudflare.com/cloudflare-one/team-and-resources/users/seat-management/#revoke-a-user) from your Zero Trust organization. |
| Access: Organizations, Identity Providers, and Groups Edit | Grants write access to [Zero Trust Organization settings](https://developers.cloudflare.com/api/resources/zero_trust/subresources/organizations/methods/list/), [Cloudflare One identity providers](https://developers.cloudflare.com/cloudflare-one/integrations/identity-providers/), and [Cloudflare Access rule groups](https://developers.cloudflare.com/cloudflare-one/access-controls/policies/groups/). |
| Access: Policies Read | Grants read access to [Cloudflare Access policies](https://developers.cloudflare.com/cloudflare-one/access-controls/policies/policy-management/). |
| Access: Policies Edit | Grants write access to [Cloudflare Access policies](https://developers.cloudflare.com/cloudflare-one/access-controls/policies/policy-management/). |
| Access: Policy Test Read | Grants read access to Cloudflare Access policy test [results](https://developers.cloudflare.com/api/resources/zero_trust/subresources/access/subresources/applications/subresources/policy_tests/subresources/users/methods/list/) and [status](https://developers.cloudflare.com/api/resources/zero_trust/subresources/access/subresources/applications/subresources/policy_tests/methods/get/). |
| Access: Policy Test Edit | Grants access to [test Cloudflare Access policies](https://developers.cloudflare.com/cloudflare-one/access-controls/policies/policy-management/#test-your-policies). |
| Access: Population Read | Grants read access to the [SCIM users and groups](https://developers.cloudflare.com/cloudflare-one/team-and-resources/users/scim/) synced from an identity provider to Cloudflare Access. |
| Access: Population Edit | Grants write access to the [SCIM users and groups](https://developers.cloudflare.com/cloudflare-one/team-and-resources/users/scim/) synced from an identity provider to Cloudflare Access. |
| Access: SCIM Logs Read | Grants read access to [Cloudflare Access SCIM provisioning logs](https://developers.cloudflare.com/cloudflare-one/insights/logs/dashboard-logs/scim-logs/). |
| Access: Service Tokens Read | Grants read access to [Cloudflare Access service tokens](https://developers.cloudflare.com/cloudflare-one/access-controls/service-credentials/service-tokens/). |
| Access: Service Tokens Edit | Grants write access to [Cloudflare Access service tokens](https://developers.cloudflare.com/cloudflare-one/access-controls/service-credentials/service-tokens/). |
| Access: SSH Auditing Read | Grants read access to [Cloudflare Access SSH CAs](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/use-cases/ssh/ssh-infrastructure-access/). |
| Access: SSH Auditing Edit | Grants write access to [Cloudflare Access SSH CAs](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/use-cases/ssh/ssh-infrastructure-access/). |
| Access: Tags Read | Grants read access to [Cloudflare Access tags](https://developers.cloudflare.com/cloudflare-one/reusable-components/tags/). |
| Access: Tags Edit | Grants write access to [Cloudflare Access tags](https://developers.cloudflare.com/cloudflare-one/reusable-components/tags/). |
| Access: Users Read | Grants read access to [users in a Zero Trust organization](https://developers.cloudflare.com/cloudflare-one/team-and-resources/users/). |
| Access: Users Edit | Grants access to update a user's name in a Zero Trust organization. |
| Account Analytics Read | Grants read access to [account analytics](https://developers.cloudflare.com/analytics/account-and-zone-analytics/account-analytics/). |
| Account Custom Pages Read | Grants read access to account-level [Error Pages](https://developers.cloudflare.com/rules/custom-errors/). |
| Account Custom Pages Edit | Grants write access to account-level [Error Pages](https://developers.cloudflare.com/rules/custom-errors/). |
| Account Filter Lists Read | Grants read access to Account Filter Lists. |
| Account Filter Lists Edit | Grants write access to Account Filter Lists. |
| Account Firewall Access Rules Read | Grants read access to account firewall access rules. |
| Account Firewall Access Rules Edit | Grants write access to account firewall access rules. |
| Account Rulesets Read | Grants read access to [Account Rulesets](https://developers.cloudflare.com/ruleset-engine/about/rulesets/). |
| Account Rulesets Edit | Grants write access to [Account Rulesets](https://developers.cloudflare.com/ruleset-engine/about/rulesets/). |
| Account Security Center Insights | Grants read access to [Security Center Insights](https://developers.cloudflare.com/security/security-insights/). |
| Account Security Center Insights Edit | Grants write access to [Security Center Insights](https://developers.cloudflare.com/security/security-insights/). |
| Account Settings Read | Grants read access to [Account resources, account membership, and account level features](https://developers.cloudflare.com/fundamentals/account/). |
| Account Settings Edit | Grants write access to [Account resources, account membership, and account level features](https://developers.cloudflare.com/fundamentals/account/). |
| Account: SSL and Certificates Read | Grants read access to [SSL and Certificates](https://developers.cloudflare.com/ssl/). |
| Account: SSL and Certificates Edit | Grants write access to [SSL and Certificates](https://developers.cloudflare.com/ssl/). |
| Account WAF Read | Grants read access to [Account WAF](https://developers.cloudflare.com/waf/). |
| Account WAF Edit | Grants write access to [Account WAF](https://developers.cloudflare.com/waf/). |
| Address Maps Edit | Grants write access to [Address Maps](https://developers.cloudflare.com/byoip/address-maps/) |
| Address Maps Read | Grants read access to [Address Maps](https://developers.cloudflare.com/byoip/address-maps/) |
| Address Maps Read | Grants read access to [Address Maps](https://developers.cloudflare.com/byoip/address-maps/) |
| AI Gateway Edit | Grants edit access to [AI Gateway](https://developers.cloudflare.com/ai-gateway/) |
| AI Gateway Read | Grants read access to [AI Gateway](https://developers.cloudflare.com/ai-gateway/) |
| AI Gateway Run | Grants run access to [Non-realtime WebSockets API](https://developers.cloudflare.com/ai-gateway/usage/websockets-api/non-realtime-api/) |
| Allow Request Tracer Read | Grants read access to Request Tracer. |
| API Gateway Read | Grants read access to [API Gateway (including API Shield)](https://developers.cloudflare.com/api-shield/) for all domains in an account. |
| API Gateway Edit | Grants write access to [API Gateway (including API Shield)](https://developers.cloudflare.com/api-shield/) for all domains in an account. |
| Billing Read | Grants read access to [billing profile, subscriptions, and access to fetch invoices](https://developers.cloudflare.com/billing/) and entitlements. |
| Billing Edit | Grants write access to [billing profile, subscriptions, and access to fetch invoices and entitlements](https://developers.cloudflare.com/billing/). |
| Bulk URL Redirects Read | Grants read access to [Bulk Redirects](https://developers.cloudflare.com/rules/url-forwarding/bulk-redirects/). |
| Bulk URL Redirects Edit | Grants write access to [Bulk Redirects](https://developers.cloudflare.com/rules/url-forwarding/bulk-redirects/). |
| China Network Steering Read | Grants read access to [China Network Steering](https://developers.cloudflare.com/china-network/). |
| China Network Steering Edit | Grants write access to [China Network Steering](https://developers.cloudflare.com/china-network/). |
| Cloudchamber Read | Grants read access to Cloudchamber deployments. |
| Cloudchamber Edit | Grants write access to Cloudchamber deployments. |
| Cloudflare Realtime Read | Grants read access to Cloudflare Realtime. |
| Cloudflare Realtime Edit | Grants write access to Cloudflare Realtime. |
| Cloudflare CASB Read | Grants read access to [Cloud Access Security Broker](https://developers.cloudflare.com/cloudflare-one/cloud-and-saas-findings/). |
| Cloudflare CASB Edit | Grants write access to [Cloud Access Security Broker](https://developers.cloudflare.com/cloudflare-one/cloud-and-saas-findings/). |
| Cloudflare DEX Read | Grants read access to [Digital Experience Monitoring](https://developers.cloudflare.com/cloudflare-one/insights/dex/). |
| Cloudflare DEX Edit | Grants write access to [Digital Experience Monitoring](https://developers.cloudflare.com/cloudflare-one/insights/dex/). |
| Cloudflare Images Read | Grants read access to [Cloudflare Images](https://developers.cloudflare.com/images/). |
| Cloudflare Images Edit | Grants write access to [Cloudflare Images](https://developers.cloudflare.com/images/). |
| Cloudflare One Connector: cloudflared Read | Grants read access to [`cloudflared` connectors](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/) |
| Cloudflare One Connector: cloudflared Edit | Grants write access to [`cloudflared` connectors](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/) |
| Cloudflare One Connector: WARP Read | Grants read access to [Cloudflare Mesh nodes](https://developers.cloudflare.com/mesh/) |
| Cloudflare One Connector: WARP Edit | Grants write access to [Cloudflare Mesh nodes](https://developers.cloudflare.com/mesh/) |
| Cloudflare One Connectors Read | Grants read access to Cloudflare One connectors |
| Cloudflare One Connectors Edit | Grants write access to Cloudflare One connectors |
| Cloudflare One Networks Read | Grants read access to Cloudflare One routes and virtual networks |
| Cloudflare One Networks Edit | Grants write access to Cloudflare One routes and virtual networks |
| Cloudflare Pages Read | Grants access to view [Cloudflare Pages](https://developers.cloudflare.com/pages/) projects. |
| Cloudflare Pages Edit | Grants access to create, edit and delete [Cloudflare Pages](https://developers.cloudflare.com/pages/) projects. |
| Cloudflare Tunnel Read | Grants access to view [Cloudflare Tunnels](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/). |
| Cloudflare Tunnel Edit | Grants access to create and delete [Cloudflare Tunnels](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/). |
| Cloudforce One Read | Grants read access to Cloudforce One. |
| Cloudforce One Edit | Grants write access to Cloudforce One. |
| Email Security Read | Grants read access to [Cloud Email Security](https://developers.cloudflare.com/email-security/). |
| Email Security Edit | Grants write access to [Email Security](https://developers.cloudflare.com/email-security/). |
| Constellation Read | Grants read access to [Constellation](https://developers.cloudflare.com/constellation/). |
| Constellation Edit | Grants write access to [Constellation](https://developers.cloudflare.com/constellation/). |
| Containers Read | Grants read access to [Containers](https://developers.cloudflare.com/containers/). |
| Containers Edit | Grants write access to [Containers](https://developers.cloudflare.com/containers/). |
| D1 Read | Grants read access to [D1](https://developers.cloudflare.com/d1/). |
| D1 Edit | Grants write access to [D1](https://developers.cloudflare.com/d1/). |
| DDoS Botnet Feed Read | Grants read access to Botnet Feed reports. |
| DDoS Botnet Feed Edit | Grants write access to Botnet Feed configuration. |
| DDoS Protection Read | Grants read access to [DDoS protection](https://developers.cloudflare.com/ddos-protection/). |
| DDoS Protection Edit | Grants write access to [DDoS protection](https://developers.cloudflare.com/ddos-protection/). |
| DNS Firewall Read | Grants read access to [DNS Firewall](https://developers.cloudflare.com/dns/dns-firewall/). |
| DNS Firewall Edit | Grants write access to [DNS Firewall](https://developers.cloudflare.com/dns/dns-firewall/). |
| Email Routing Addresses Read | Grants read access to [Email Routing Addresses](https://developers.cloudflare.com/email-service/configuration/email-routing-addresses/). |
| Email Routing Addresses Edit | Grants write access to [Email Routing Addresses](https://developers.cloudflare.com/email-service/configuration/email-routing-addresses/). |
| Hyperdrive Read | Grants read access to [Hyperdrive](https://developers.cloudflare.com/hyperdrive/). |
| Hyperdrive Edit | Grants write access to [Hyperdrive](https://developers.cloudflare.com/hyperdrive/). |
| Intel Read | Grants read access to [Intel](https://developers.cloudflare.com/security-center/intel-apis/). |
| Intel Edit | Grants write access to [Intel](https://developers.cloudflare.com/security-center/intel-apis/). |
| Integration Edit | Grants write access to integrations. |
| IOT Read | Grants read access to [IOT ↗︎](https://blog.cloudflare.com/rethinking-internet-of-things-security/). |
| IOT Edit | Grants write access to [IOT ↗︎](https://blog.cloudflare.com/rethinking-internet-of-things-security/). |
| IP Prefixes: Read | Grants access to read IP prefix settings. |
| IP Prefixes: Edit | Grants access to read/write IP prefix settings. |
| IP Prefixes: BGP On Demand Read | Grants access to read IP prefix BGP configuration. |
| IP Prefixes: BGP On Demand Edit | Grants access to read and change IP prefix BGP configuration. |
| L3/4 DDoS Managed Ruleset Read | Grants read access to [L3/4 DDoS managed ruleset](https://developers.cloudflare.com/ddos-protection/managed-rulesets/network/). |
| L3/4 DDoS Managed Ruleset Edit | Grants write access to [L3/4 DDoS managed ruleset](https://developers.cloudflare.com/ddos-protection/managed-rulesets/network/). |
| Load Balancing: Monitors and Pools Read | Grants read access to account level [load balancer resources](https://developers.cloudflare.com/load-balancing/). |
| Load Balancing: Monitors and Pools Edit | Grants write access to account level [load balancer resources](https://developers.cloudflare.com/load-balancing/). |
| Logs Read | Grants read access to logs using [Logpull or Instant Logs](https://developers.cloudflare.com/logs/). |
| Logs Edit | Grants read and write access to [Logpull, Logpush, and Instant Logs](https://developers.cloudflare.com/logs/). |
| Magic Firewall Read | Grants read access to [Cloudflare Network Firewall](https://developers.cloudflare.com/cloudflare-network-firewall/). |
| Magic Firewall Edit | Grants write access to [Cloudflare Network Firewall](https://developers.cloudflare.com/cloudflare-network-firewall/). |
| Magic Firewall Packet Captures Read | Grants read access to [Packet Captures](https://developers.cloudflare.com/cloudflare-network-firewall/packet-captures/collect-pcaps/). |
| Magic Firewall Packet Captures Edit | Grants write access to [Packet Captures](https://developers.cloudflare.com/cloudflare-network-firewall/packet-captures/collect-pcaps/). |
| Magic Network Monitoring Read | Grants read access to [Network Flow](https://developers.cloudflare.com/network-flow/). |
| Magic Network Monitoring Edit | Grants write access to [Network Flow](https://developers.cloudflare.com/network-flow/). |
| Magic Transit Read | Grants read access to manage a user's [Magic Transit prefixes](https://developers.cloudflare.com/magic-transit/how-to/advertise-prefixes/). |
| Magic Transit Edit | Grants write access to manage a user's [Magic Transit prefixes](https://developers.cloudflare.com/magic-transit/how-to/advertise-prefixes/). |
| Notifications Read | Grants read access to [Notifications](https://developers.cloudflare.com/notifications/). |
| Notifications Edit | Grants write access to [Notifications](https://developers.cloudflare.com/notifications/). |
| Client-side security Read | Grants read access to [client-side security](https://developers.cloudflare.com/client-side-security/) (previously known as Page Shield). |
| Client-side security Edit | Grants write access to [client-side security](https://developers.cloudflare.com/client-side-security/) (previously known as Page Shield). |
| Workers Pipelines Read | Grants read access to Cloudflare Pipelines. |
| Workers Pipelines Edit | Grants write access to Cloudflare Pipelines. |
| Queues Read | Grants read access to [Queues](https://developers.cloudflare.com/queues/). |
| Queues Edit | Grants write access to [Queues](https://developers.cloudflare.com/queues/). |
| Rule Policies Read | Grants read access to Rule Policies. |
| Rule Policies Edit | Grants write access to Rule Policies. |
| Stream Read | Grants read access to [Cloudflare Stream](https://developers.cloudflare.com/stream/). |
| Stream Edit | Grants write access to [Cloudflare Stream](https://developers.cloudflare.com/stream/). |
| Transform Rules Read | Grants read access to [Transform Rules](https://developers.cloudflare.com/rules/transform/). |
| Transform Rules Edit | Grants write access to [Transform Rules](https://developers.cloudflare.com/rules/transform/). |
| Turnstile Read | Grants read access to [Turnstile](https://developers.cloudflare.com/turnstile/). |
| Turnstile Edit | Grants write access to [Turnstile](https://developers.cloudflare.com/turnstile/). |
| URL Scanner Read | Grants read access to [URL Scanner](https://developers.cloudflare.com/radar/investigate/url-scanner/). |
| URL Scanner Edit | Grants write access to [URL Scanner](https://developers.cloudflare.com/radar/investigate/url-scanner/). |
| Vectorize Read | Grants read access to [Vectorize](https://developers.cloudflare.com/vectorize/). |
| Vectorize Edit | Grants write access to [Vectorize](https://developers.cloudflare.com/vectorize/). |
| Workers AI Read | Grants read access to [Workers AI](https://developers.cloudflare.com/workers-ai/). |
| Workers AI Edit | Grants write access to [Workers AI](https://developers.cloudflare.com/workers-ai/). |
| Workers CI Read | Grants read access to [Workers CI](https://developers.cloudflare.com/workers/). |
| Workers CI Edit | Grants write access to [Workers CI](https://developers.cloudflare.com/workers). |
| Workers KV Storage Read | Grants read access to [Cloudflare Workers KV Storage](https://developers.cloudflare.com/kv/api/). |
| Workers KV Storage Edit | Grants write access to [Cloudflare Workers KV Storage](https://developers.cloudflare.com/kv/api/). |
| Workers R2 Storage Read | Grants read access to [Cloudflare R2 Storage](https://developers.cloudflare.com/r2/). |
| Workers R2 Storage Edit | Grants write access to [Cloudflare R2 Storage](https://developers.cloudflare.com/r2/). |
| Workers Scripts Read | Grants read access to [Cloudflare Workers scripts](https://developers.cloudflare.com/workers/). |
| Workers Scripts Edit | Grants write access to [Cloudflare Workers scripts](https://developers.cloudflare.com/workers/). |
| Workers Tail Read | Grants [`wrangler tail`](https://developers.cloudflare.com/workers/wrangler/commands/general/#tail) read permissions. |
| Zero Trust Read | Grants read access to [Cloudflare Zero Trust](https://developers.cloudflare.com/cloudflare-one/) resources. |
| Zero Trust Report | Grants reporting access to [Cloudflare Zero Trust](https://developers.cloudflare.com/cloudflare-one/). |
| Zero Trust Edit | Grants write access to [Cloudflare Zero Trust](https://developers.cloudflare.com/cloudflare-one/) resources. |
| Zero Trust: PII Read | Grants read access to [Cloudflare Zero Trust](https://developers.cloudflare.com/cloudflare-one/) PII. |
| Zero Trust: Seats Edit | Grants write access to the number of [Zero Trust seats](https://developers.cloudflare.com/cloudflare-one/team-and-resources/users/seat-management/) your organization can use (and be billed for). |

| Name | Description |
| --- | --- |
| Access: Apps and Policies Read | Grants read access to Cloudflare Access [applications](https://developers.cloudflare.com/cloudflare-one/access-controls/applications/) and [policies](https://developers.cloudflare.com/cloudflare-one/access-controls/policies/). |
| Access: Apps and Policies Revoke | Grants ability to revoke [Cloudflare Access application tokens](https://developers.cloudflare.com/cloudflare-one/access-controls/access-settings/session-management/) |
| Access: Apps and Policies Write | Grants write access to Cloudflare Access [applications](https://developers.cloudflare.com/cloudflare-one/access-controls/applications/) and [policies](https://developers.cloudflare.com/cloudflare-one/access-controls/policies/). |
| Access: Apps Read | Grants read access to [Cloudflare Access applications](https://developers.cloudflare.com/cloudflare-one/access-controls/applications/). |
| Access: Apps Revoke | Grants ability to revoke [Cloudflare Access application tokens](https://developers.cloudflare.com/cloudflare-one/access-controls/access-settings/session-management/). |
| Access: Apps Write | Grants write access to [Cloudflare Access applications](https://developers.cloudflare.com/cloudflare-one/access-controls/applications/). |
| Access: Audit Logs Read | Grants read access to [Cloudflare Access authentication logs](https://developers.cloudflare.com/cloudflare-one/insights/logs/dashboard-logs/access-authentication-logs/). |
| Access: Custom Pages Read | Grants read access to [Cloudflare Access custom block pages](https://developers.cloudflare.com/cloudflare-one/reusable-components/custom-pages/access-block-page/). |
| Access: Custom Pages Write | Grants write access to [Cloudflare Access custom block pages](https://developers.cloudflare.com/cloudflare-one/reusable-components/custom-pages/access-block-page/). |
| Access: Device Posture Read | Grants read access to [Cloudflare Access device posture](https://developers.cloudflare.com/cloudflare-one/reusable-components/posture-checks/). |
| Access: Device Posture Write | Grants write access to [Cloudflare Access device posture](https://developers.cloudflare.com/cloudflare-one/reusable-components/posture-checks/). |
| Access: Groups Read | Grants read access to [Cloudflare Access rule groups](https://developers.cloudflare.com/cloudflare-one/access-controls/policies/groups/). |
| Access: Groups Write | Grants write access to [Cloudflare Access rule groups](https://developers.cloudflare.com/cloudflare-one/access-controls/policies/groups/). |
| Access: Identity Providers Read | Grants read access to [Cloudflare One identity providers](https://developers.cloudflare.com/cloudflare-one/integrations/identity-providers/). |
| Access: Identity Providers Write | Grants write access to [Cloudflare One identity providers](https://developers.cloudflare.com/cloudflare-one/integrations/identity-providers/). |
| Access: Keys Read | Grants read access to [Cloudflare Access signing keys](https://developers.cloudflare.com/cloudflare-one/access-controls/applications/http-apps/authorization-cookie/validating-json/). |
| Access: Keys Write | Grants ability to rotate [Cloudflare Access signing keys](https://developers.cloudflare.com/cloudflare-one/access-controls/applications/http-apps/authorization-cookie/validating-json/). |
| Access: Mutual TLS Certificates Read | Grants read access to [Cloudflare Access mTLS certificates](https://developers.cloudflare.com/cloudflare-one/access-controls/service-credentials/mutual-tls-authentication/). |
| Access: Mutual TLS Certificates Write | Grants write access to [Cloudflare Access mTLS certificates](https://developers.cloudflare.com/cloudflare-one/access-controls/service-credentials/mutual-tls-authentication/). |
| Access: Organizations Read | Grants read access to [Zero Trust Organization settings](https://developers.cloudflare.com/api/resources/zero_trust/subresources/organizations/methods/list/). |
| Access: Organizations Revoke | Grants ability to [revoke user sessions](https://developers.cloudflare.com/cloudflare-one/access-controls/access-settings/session-management/#revoke-user-sessions) in a Zero Trust organization. |
| Access: Organizations Write | Grants write access to [Zero Trust Organization settings](https://developers.cloudflare.com/api/resources/zero_trust/subresources/organizations/methods/list/). |
| Access: Organizations, Identity Providers, and Groups Read | Grants read access to [Zero Trust Organization settings](https://developers.cloudflare.com/api/resources/zero_trust/subresources/organizations/methods/list/), [Cloudflare One identity providers](https://developers.cloudflare.com/cloudflare-one/integrations/identity-providers/), and [Cloudflare Access rule groups](https://developers.cloudflare.com/cloudflare-one/access-controls/policies/groups/). |
| Access: Organizations, Identity Providers, and Groups Revoke | Grants ability to [revoke users](https://developers.cloudflare.com/cloudflare-one/team-and-resources/users/seat-management/#revoke-a-user) from your Zero Trust organization. |
| Access: Organizations, Identity Providers, and Groups Write | Grants write access to [Zero Trust Organization settings](https://developers.cloudflare.com/api/resources/zero_trust/subresources/organizations/methods/list/), [Cloudflare One identity providers](https://developers.cloudflare.com/cloudflare-one/integrations/identity-providers/), and [Cloudflare Access rule groups](https://developers.cloudflare.com/cloudflare-one/access-controls/policies/groups/). |
| Access: Policies Read | Grants read access to [Cloudflare Access policies](https://developers.cloudflare.com/cloudflare-one/access-controls/policies/policy-management/). |
| Access: Policies Write | Grants write access to [Cloudflare Access policies](https://developers.cloudflare.com/cloudflare-one/access-controls/policies/policy-management/). |
| Access: Policy Test Read | Grants read access to Cloudflare Access policy test [results](https://developers.cloudflare.com/api/resources/zero_trust/subresources/access/subresources/applications/subresources/policy_tests/subresources/users/methods/list/) and [status](https://developers.cloudflare.com/api/resources/zero_trust/subresources/access/subresources/applications/subresources/policy_tests/methods/get/). |
| Access: Policy Test Write | Grants access to [test Cloudflare Access policies](https://developers.cloudflare.com/cloudflare-one/access-controls/policies/policy-management/#test-your-policies). |
| Access: Population Read | Grants read access to the [SCIM users and groups](https://developers.cloudflare.com/cloudflare-one/team-and-resources/users/scim/) synced from an identity provider to Cloudflare Access. |
| Access: Population Write | Grants write access to the [SCIM users and groups](https://developers.cloudflare.com/cloudflare-one/team-and-resources/users/scim/) synced from an identity provider to Cloudflare Access. |
| Access: SCIM Logs Read | Grants read access to [Cloudflare Access SCIM provisioning logs](https://developers.cloudflare.com/cloudflare-one/insights/logs/dashboard-logs/scim-logs/). |
| Access: Service Tokens Read | Grants read access to [Cloudflare Access service tokens](https://developers.cloudflare.com/cloudflare-one/access-controls/service-credentials/service-tokens/). |
| Access: Service Tokens Write | Grants write access to [Cloudflare Access service tokens](https://developers.cloudflare.com/cloudflare-one/access-controls/service-credentials/service-tokens/). |
| Access: SSH Auditing Read | Grants read access to [Cloudflare Access SSH CAs](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/use-cases/ssh/ssh-infrastructure-access/). |
| Access: SSH Auditing Write | Grants write access to [Cloudflare Access SSH CAs](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/use-cases/ssh/ssh-infrastructure-access/). |
| Access: Tags Read | Grants read access to [Cloudflare Access tags](https://developers.cloudflare.com/cloudflare-one/reusable-components/tags/). |
| Access: Tags Write | Grants write access to [Cloudflare Access tags](https://developers.cloudflare.com/cloudflare-one/reusable-components/tags/). |
| Access: Users Read | Grants read access to [users in a Zero Trust organization](https://developers.cloudflare.com/cloudflare-one/team-and-resources/users/). |
| Access: Users Write | Grants access to update a user's name in a Zero Trust organization. |
| Account Analytics Read | Grants read access to [account analytics](https://developers.cloudflare.com/analytics/account-and-zone-analytics/account-analytics/). |
| Account Custom Pages Read | Grants read access to account-level [Error Pages](https://developers.cloudflare.com/rules/custom-errors/). |
| Account Custom Pages Write | Grants write access to account-level [Error Pages](https://developers.cloudflare.com/rules/custom-errors/). |
| Account Rule Lists Read | Grants read access to Account Filter Lists. |
| Account Rule Lists Write | Grants write access to Account Filter Lists. |
| Account Firewall Access Rules Read | Grants read access to account firewall access rules. |
| Account Firewall Access Rules Write | Grants write access to account firewall access rules. |
| Account Rulesets Read | Grants read access to [Account Rulesets](https://developers.cloudflare.com/ruleset-engine/about/rulesets/). |
| Account Rulesets Write | Grants write access to [Account Rulesets](https://developers.cloudflare.com/ruleset-engine/about/rulesets/). |
| Account Security Center Insights | Grants read access to [Security Center Insights](https://developers.cloudflare.com/security/security-insights/). |
| Account Security Center Insights Write | Grants write access to [Security Center Insights](https://developers.cloudflare.com/security/security-insights/). |
| Account Settings Read | Grants read access to [Account resources, account membership, and account level features](https://developers.cloudflare.com/fundamentals/account/). |
| Account Settings Write | Grants write access to [Account resources, account membership, and account level features](https://developers.cloudflare.com/fundamentals/account/). |
| Account: SSL and Certificates Read | Grants read access to [SSL and Certificates](https://developers.cloudflare.com/ssl/). |
| Account: SSL and Certificates Write | Grants write access to [SSL and Certificates](https://developers.cloudflare.com/ssl/). |
| Account WAF Read | Grants read access to [Account WAF](https://developers.cloudflare.com/waf/). |
| Account WAF Write | Grants write access to [Account WAF](https://developers.cloudflare.com/waf/). |
| Address Maps Write | Grants write access to [Address Maps](https://developers.cloudflare.com/byoip/address-maps/) |
| Address Maps Read | Grants read access to [Address Maps](https://developers.cloudflare.com/byoip/address-maps/) |
| Address Maps Read | Grants read access to [Address Maps](https://developers.cloudflare.com/byoip/address-maps/) |
| AI Gateway Edit | Grants edit access to [AI Gateway](https://developers.cloudflare.com/ai-gateway/) |
| AI Gateway Read | Grants read access to [AI Gateway](https://developers.cloudflare.com/ai-gateway/) |
| AI Gateway Run | Grants run access to [Non-realtime WebSockets API](https://developers.cloudflare.com/ai-gateway/usage/websockets-api/non-realtime-api/) |
| Allow Request Tracer Read | Grants read access to Request Tracer. |
| Account API Gateway Read | Grants read access to [API Gateway (including API Shield)](https://developers.cloudflare.com/api-shield/) for all domains in an account. |
| Account API Gateway Write | Grants write access to [API Gateway (including API Shield)](https://developers.cloudflare.com/api-shield/) for all domains in an account. |
| Billing Read | Grants read access to [billing profile, subscriptions, and access to fetch invoices](https://developers.cloudflare.com/billing/) and entitlements. |
| Billing Write | Grants write access to [billing profile, subscriptions, and access to fetch invoices and entitlements](https://developers.cloudflare.com/billing/). |
| Mass URL Redirects Read | Grants read access to [Bulk Redirects](https://developers.cloudflare.com/rules/url-forwarding/bulk-redirects/). |
| Mass URL Redirects Write | Grants write access to [Bulk Redirects](https://developers.cloudflare.com/rules/url-forwarding/bulk-redirects/). |
| China Network Steering Read | Grants read access to [China Network Steering](https://developers.cloudflare.com/china-network/). |
| China Network Steering Write | Grants write access to [China Network Steering](https://developers.cloudflare.com/china-network/). |
| Cloudchamber Read | Grants read access to Cloudchamber deployments. |
| Cloudchamber Write | Grants write access to Cloudchamber deployments. |
| Realtime Read | Grants read access to Cloudflare Realtime. |
| Realtime Write | Grants write access to Cloudflare Realtime. |
| Cloudflare CASB Read | Grants read access to [Cloud Access Security Broker](https://developers.cloudflare.com/cloudflare-one/cloud-and-saas-findings/). |
| Cloudflare CASB Write | Grants write access to [Cloud Access Security Broker](https://developers.cloudflare.com/cloudflare-one/cloud-and-saas-findings/). |
| Cloudflare DEX Read | Grants read access to [Digital Experience Monitoring](https://developers.cloudflare.com/cloudflare-one/insights/dex/). |
| Cloudflare DEX Write | Grants write access to [Digital Experience Monitoring](https://developers.cloudflare.com/cloudflare-one/insights/dex/). |
| Images Read | Grants read access to [Cloudflare Images](https://developers.cloudflare.com/images/). |
| Images Write | Grants write access to [Cloudflare Images](https://developers.cloudflare.com/images/). |
| Cloudflare One Connector: cloudflared Read | Grants read access to [`cloudflared` connectors](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/) |
| Cloudflare One Connector: cloudflared Write | Grants write access to [`cloudflared` connectors](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/) |
| Cloudflare One Connector: WARP Read | Grants read access to [Cloudflare Mesh nodes](https://developers.cloudflare.com/mesh/) |
| Cloudflare One Connector: WARP Write | Grants write access to [Cloudflare Mesh nodes](https://developers.cloudflare.com/mesh/) |
| Cloudflare One Connectors Read | Grants read access to Cloudflare One connectors |
| Cloudflare One Connectors Write | Grants write access to Cloudflare One connectors |
| Cloudflare One Networks Read | Grants read access to Cloudflare One routes and virtual networks |
| Cloudflare One Networks Write | Grants write access to Cloudflare One routes and virtual networks |
| Pages Read | Grants access to view [Cloudflare Pages](https://developers.cloudflare.com/pages/) projects. |
| Pages Write | Grants access to create, edit and delete [Cloudflare Pages](https://developers.cloudflare.com/pages/) projects. |
| Cloudflare Tunnel Read | Grants access to view [Cloudflare Tunnels](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/). |
| Cloudflare Tunnel Write | Grants access to create and delete [Cloudflare Tunnels](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/). |
| Cloudforce One Read | Grants read access to Cloudforce One. |
| Cloudforce One Write | Grants write access to Cloudforce One. |
| Cloud Email Security: Read | Grants read access to [Cloud Email Security](https://developers.cloudflare.com/email-security/). |
| Cloud Email Security: Write | Grants write access to [Email Security](https://developers.cloudflare.com/email-security/). |
| Constellation Read | Grants read access to [Constellation](https://developers.cloudflare.com/constellation/). |
| Constellation Write | Grants write access to [Constellation](https://developers.cloudflare.com/constellation/). |
| Containers Read | Grants read access to [Containers](https://developers.cloudflare.com/containers/). |
| Containers Write | Grants write access to [Containers](https://developers.cloudflare.com/containers/). |
| D1 Read | Grants read access to [D1](https://developers.cloudflare.com/d1/). |
| D1 Write | Grants write access to [D1](https://developers.cloudflare.com/d1/). |
| DDoS Botnet Feed Read | Grants read access to Botnet Feed reports. |
| DDoS Botnet Feed Write | Grants write access to Botnet Feed configuration. |
| DDoS Protection Read | Grants read access to [DDoS protection](https://developers.cloudflare.com/ddos-protection/). |
| DDoS Protection Write | Grants write access to [DDoS protection](https://developers.cloudflare.com/ddos-protection/). |
| DNS Firewall Read | Grants read access to [DNS Firewall](https://developers.cloudflare.com/dns/dns-firewall/). |
| DNS Firewall Write | Grants write access to [DNS Firewall](https://developers.cloudflare.com/dns/dns-firewall/). |
| Email Routing Addresses Read | Grants read access to [Email Routing Addresses](https://developers.cloudflare.com/email-service/configuration/email-routing-addresses/). |
| Email Routing Addresses Write | Grants write access to [Email Routing Addresses](https://developers.cloudflare.com/email-service/configuration/email-routing-addresses/). |
| Hyperdrive Read | Grants read access to [Hyperdrive](https://developers.cloudflare.com/hyperdrive/). |
| Hyperdrive Write | Grants write access to [Hyperdrive](https://developers.cloudflare.com/hyperdrive/). |
| Intel Read | Grants read access to [Intel](https://developers.cloudflare.com/security-center/intel-apis/). |
| Intel Write | Grants write access to [Intel](https://developers.cloudflare.com/security-center/intel-apis/). |
| Integration Write | Grants write access to integrations. |
| IOT Read | Grants read access to [IOT ↗︎](https://blog.cloudflare.com/rethinking-internet-of-things-security/). |
| IOT Write | Grants write access to [IOT ↗︎](https://blog.cloudflare.com/rethinking-internet-of-things-security/). |
| IP Prefixes: Read | Grants access to read IP prefix settings. |
| IP Prefixes: Write | Grants access to read/write IP prefix settings. |
| IP Prefixes: BGP On Demand Read | Grants access to read IP prefix BGP configuration. |
| IP Prefixes: BGP On Demand Write | Grants access to read and change IP prefix BGP configuration. |
| L4 DDoS Managed Ruleset Read | Grants read access to [L3/4 DDoS managed ruleset](https://developers.cloudflare.com/ddos-protection/managed-rulesets/network/). |
| L4 DDoS Managed Ruleset Write | Grants write access to [L3/4 DDoS managed ruleset](https://developers.cloudflare.com/ddos-protection/managed-rulesets/network/). |
| Load Balancing: Monitors and Pools Read | Grants read access to account level [load balancer resources](https://developers.cloudflare.com/load-balancing/). |
| Load Balancing: Monitors and Pools Write | Grants write access to account level [load balancer resources](https://developers.cloudflare.com/load-balancing/). |
| Logs Read | Grants read access to logs using [Logpull or Instant Logs](https://developers.cloudflare.com/logs/). |
| Logs Write | Grants read and write access to [Logpull, Logpush, and Instant Logs](https://developers.cloudflare.com/logs/). |
| Magic Firewall Read | Grants read access to [Cloudflare Network Firewall](https://developers.cloudflare.com/cloudflare-network-firewall/). |
| Magic Firewall Write | Grants write access to [Cloudflare Network Firewall](https://developers.cloudflare.com/cloudflare-network-firewall/). |
| Magic Firewall Packet Captures - Read PCAPs API | Grants read access to [Packet Captures](https://developers.cloudflare.com/cloudflare-network-firewall/packet-captures/collect-pcaps/). |
| Magic Firewall Packet Captures - Write PCAPs API | Grants write access to [Packet Captures](https://developers.cloudflare.com/cloudflare-network-firewall/packet-captures/collect-pcaps/). |
| Magic Network Monitoring Read | Grants read access to [Network Flow](https://developers.cloudflare.com/network-flow/). |
| Magic Network Monitoring Write | Grants write access to [Network Flow](https://developers.cloudflare.com/network-flow/). |
| Magic Transit Read | Grants read access to manage a user's [Magic Transit prefixes](https://developers.cloudflare.com/magic-transit/how-to/advertise-prefixes/). |
| Magic Transit Write | Grants write access to manage a user's [Magic Transit prefixes](https://developers.cloudflare.com/magic-transit/how-to/advertise-prefixes/). |
| Notifications Read | Grants read access to [Notifications](https://developers.cloudflare.com/notifications/). |
| Notifications Write | Grants write access to [Notifications](https://developers.cloudflare.com/notifications/). |
| Page Shield Read | Grants read access to [client-side security](https://developers.cloudflare.com/client-side-security/) (previously known as Page Shield). |
| Page Shield Write | Grants write access to [client-side security](https://developers.cloudflare.com/client-side-security/) (previously known as Page Shield). |
| Pipelines Read | Grants read access to Cloudflare Pipelines. |
| Pipelines Write | Grants write access to Cloudflare Pipelines. |
| Queues Read | Grants read access to [Queues](https://developers.cloudflare.com/queues/). |
| Queues Write | Grants write access to [Queues](https://developers.cloudflare.com/queues/). |
| Rule Policies Read | Grants read access to Rule Policies. |
| Rule Policies Write | Grants write access to Rule Policies. |
| Stream Read | Grants read access to [Cloudflare Stream](https://developers.cloudflare.com/stream/). |
| Stream Write | Grants write access to [Cloudflare Stream](https://developers.cloudflare.com/stream/). |
| Transform Rules Read | Grants read access to [Transform Rules](https://developers.cloudflare.com/rules/transform/). |
| Transform Rules Write | Grants write access to [Transform Rules](https://developers.cloudflare.com/rules/transform/). |
| Turnstile Read | Grants read access to [Turnstile](https://developers.cloudflare.com/turnstile/). |
| Turnstile Write | Grants write access to [Turnstile](https://developers.cloudflare.com/turnstile/). |
| URL Scanner Read | Grants read access to [URL Scanner](https://developers.cloudflare.com/radar/investigate/url-scanner/). |
| URL Scanner Write | Grants write access to [URL Scanner](https://developers.cloudflare.com/radar/investigate/url-scanner/). |
| Vectorize Read | Grants read access to [Vectorize](https://developers.cloudflare.com/vectorize/). |
| Vectorize Write | Grants write access to [Vectorize](https://developers.cloudflare.com/vectorize/). |
| Workers AI Read | Grants read access to [Workers AI](https://developers.cloudflare.com/workers-ai/). |
| Workers AI Write | Grants write access to [Workers AI](https://developers.cloudflare.com/workers-ai/). |
| Workers CI Read | Grants read access to [Workers CI](https://developers.cloudflare.com/workers/). |
| Workers CI Write | Grants write access to [Workers CI](https://developers.cloudflare.com/workers). |
| Workers KV Storage Read | Grants read access to [Cloudflare Workers KV Storage](https://developers.cloudflare.com/kv/api/). |
| Workers KV Storage Write | Grants write access to [Cloudflare Workers KV Storage](https://developers.cloudflare.com/kv/api/). |
| Workers R2 Storage Read | Grants read access to [Cloudflare R2 Storage](https://developers.cloudflare.com/r2/). |
| Workers R2 Storage Write | Grants write access to [Cloudflare R2 Storage](https://developers.cloudflare.com/r2/). |
| Workers Scripts Read | Grants read access to [Cloudflare Workers scripts](https://developers.cloudflare.com/workers/). |
| Workers Scripts Write | Grants write access to [Cloudflare Workers scripts](https://developers.cloudflare.com/workers/). |
| Workers Tail Read | Grants [`wrangler tail`](https://developers.cloudflare.com/workers/wrangler/commands/general/#tail) read permissions. |
| Zero Trust Read | Grants read access to [Cloudflare Zero Trust](https://developers.cloudflare.com/cloudflare-one/) resources. |
| Zero Trust Report | Grants reporting access to [Cloudflare Zero Trust](https://developers.cloudflare.com/cloudflare-one/). |
| Zero Trust Write | Grants write access to [Cloudflare Zero Trust](https://developers.cloudflare.com/cloudflare-one/) resources. |
| Zero Trust: PII Read | Grants read access to [Cloudflare Zero Trust](https://developers.cloudflare.com/cloudflare-one/) PII. |
| Zero Trust: Seats Write | Grants write access to the number of [Zero Trust seats](https://developers.cloudflare.com/cloudflare-one/team-and-resources/users/seat-management/) your organization can use (and be billed for). |

## Zone permissions

The applicable scope of zone permissions is `com.cloudflare.api.account.zone`.

| Name | Description |
| --- | --- |
| Access: Apps and Policies Read | Grants read access to [Cloudflare Access](https://developers.cloudflare.com/cloudflare-one/access-controls/policies/) zone resources. |
| Access: Apps and Policies Revoke | Grants ability to revoke all tokens to [Cloudflare Access](https://developers.cloudflare.com/cloudflare-one/access-controls/policies/) zone resources. |
| Access: Apps and Policies Edit | Grants write access to [Cloudflare Access](https://developers.cloudflare.com/cloudflare-one/access-controls/policies/) zone resources. |
| Analytics Read | Grants read access to [analytics](https://developers.cloudflare.com/analytics/account-and-zone-analytics/zone-analytics/). |
| API Gateway Read | Grants read access to [API Gateway](https://developers.cloudflare.com/api-shield/) zone resources. |
| API Gateway Edit | Grants write access to [API Gateway](https://developers.cloudflare.com/api-shield/) zone resources. |
| Apps Edit | Grants full access to Cloudflare Apps (deprecated, refer to [Workers](https://developers.cloudflare.com/workers/) instead). |
| Bot Management Read | Grants read access to [Bot Management](https://developers.cloudflare.com/bots/plans/bm-subscription/). |
| Bot Management Edit | Grants write access to [Bot Management](https://developers.cloudflare.com/bots/plans/bm-subscription/). |
| Bot Management Feedback Read | Grants read access to [Bot Management feedback](https://developers.cloudflare.com/bots/concepts/feedback-loop/). |
| Bot Management Feedback Edit | Grants write access to [Bot Management feedback](https://developers.cloudflare.com/bots/concepts/feedback-loop/). |
| Cache Purge | Grants access to [purge cache](https://developers.cloudflare.com/cache/how-to/purge-cache/). |
| Cache Rules Read | Grants read access to [Cache Rules](https://developers.cloudflare.com/cache/how-to/cache-rules/). |
| Cache Rules Edit | Grants write access to [Cache Rules](https://developers.cloudflare.com/cache/how-to/cache-rules/). |
| Cloud Connector Read | Grants read access to [Cloud Connector rules](https://developers.cloudflare.com/rules/cloud-connector/). |
| Cloud Connector Edit | Grants write access to [Cloud Connector rules](https://developers.cloudflare.com/rules/cloud-connector/). |
| Config Rules Read | Grants read access to [Configuration Rules](https://developers.cloudflare.com/rules/configuration-rules/). |
| Config Rules Edit | Grants write access to [Configuration Rules](https://developers.cloudflare.com/rules/configuration-rules/). |
| Custom Error Rules Read | Grants read access to [Custom Error Rules](https://developers.cloudflare.com/rules/custom-errors/). |
| Custom Error Rules Edit | Grants write access to [Custom Error Rules](https://developers.cloudflare.com/rules/custom-errors/). |
| Custom Pages Read | Grants read access to [Custom Error Pages](https://developers.cloudflare.com/rules/custom-errors/). |
| Custom Pages Edit | Grants write access to [Custom Error Pages](https://developers.cloudflare.com/rules/custom-errors/). |
| Dmarc Management Read | Grants read access to [DMARC Management](https://developers.cloudflare.com/dmarc-management/). |
| Dmarc Management Edit | Grants write access to [DMARC Management](https://developers.cloudflare.com/dmarc-management/). |
| DNS Read | Grants read access to [DNS](https://developers.cloudflare.com/dns/). |
| DNS Write | Grants write access to [DNS](https://developers.cloudflare.com/dns/). |
| Email Routing Rules Read | Grants read access to [Email Routing Rules](https://developers.cloudflare.com/email-service/configuration/email-routing-addresses/). |
| Email Routing Rules Edit | Grants write access to [Email Routing Rules](https://developers.cloudflare.com/email-service/configuration/email-routing-addresses/). |
| Firewall Services Read | Grants read access to Firewall resources. |
| Firewall Services Edit | Grants write access to Firewall resources. |
| Health Checks Read | Grants read access to [Health Checks](https://developers.cloudflare.com/health-checks/). |
| Health Checks Edit | Grants write access to [Health Checks](https://developers.cloudflare.com/health-checks/). |
| HTTP DDoS Managed Ruleset Read | Grants read access to [HTTP DDoS managed ruleset](https://developers.cloudflare.com/ddos-protection/managed-rulesets/http/). |
| HTTP DDoS Managed Ruleset Edit | Grants write access to [HTTP DDoS managed ruleset](https://developers.cloudflare.com/ddos-protection/managed-rulesets/http/). |
| Load Balancers Read | Grants read access to [load balancer resources](https://developers.cloudflare.com/load-balancing/). |
| Load Balancers Edit | Grants write access to [load balancer resources](https://developers.cloudflare.com/load-balancing/). |
| Logs Read | Grants read access to logs using [Logpull](https://developers.cloudflare.com/logs/). |
| Logs Edit | Grants write access to [Logpull and Logpush](https://developers.cloudflare.com/logs/). |
| Managed Headers Read | Grants read access to [Managed Headers](https://developers.cloudflare.com/rules/transform/managed-transforms/). |
| Managed Headers Edit | Grants write access to [Managed Headers](https://developers.cloudflare.com/rules/transform/managed-transforms/). |
| Origin Rules Read | Grants read access to [Origin Rules](https://developers.cloudflare.com/rules/origin-rules/). |
| Origin Rules Edit | Grants write access to [Origin Rules](https://developers.cloudflare.com/rules/origin-rules/). |
| Page Rules Read | Grants read access to [Page Rules](https://developers.cloudflare.com/rules/page-rules/). |
| Page Rules Edit | Grants write access to [Page Rules](https://developers.cloudflare.com/rules/page-rules/). |
| Client-side security Read | Grants read access to [client-side security](https://developers.cloudflare.com/client-side-security/) (previously known as Page Shield). |
| Client-side security Edit | Grants write access to [client-side security](https://developers.cloudflare.com/client-side-security/) (previously known as Page Shield). |
| Response Compression Read | Grants read access to [Response Compression](https://developers.cloudflare.com/rules/compression-rules/). |
| Response Compression Edit | Grants write access to [Response Compression](https://developers.cloudflare.com/rules/compression-rules/). |
| Sanitize Read | Grants read access to sanitization. |
| Sanitize Edit | Grants write access to sanitization. |
| Single Redirect Read | Grants read access to zone-level [Single Redirects](https://developers.cloudflare.com/rules/url-forwarding/single-redirects/). |
| Single Redirect Edit | Grants write access to zone-level [Single Redirects](https://developers.cloudflare.com/rules/url-forwarding/single-redirects/). |
| SSL and Certificates Read | Grants read access to [SSL configuration and certificate management](https://developers.cloudflare.com/ssl/). |
| SSL and Certificates Edit | Grants write access to [SSL configuration and certificate management](https://developers.cloudflare.com/ssl/). |
| Transform Rules Read | Grants read access to [Transform Rules](https://developers.cloudflare.com/rules/transform/). |
| Transform Rules Edit | Grants write access to [Transform Rules](https://developers.cloudflare.com/rules/transform/). |
| Waiting Room Read | Grants read access to [Waiting Room](https://developers.cloudflare.com/waiting-room/). |
| Waiting Room Edit | Grants write access to [Waiting Room](https://developers.cloudflare.com/waiting-room/). |
| Web3 Hostnames Read | Grants read access to [Web3 Hostnames](https://developers.cloudflare.com/web3/). |
| Web3 Hostnames Edit | Grants write access to [Web3 Hostnames](https://developers.cloudflare.com/web3/). |
| Workers Routes Read | Grants read access to [Cloudflare Workers](https://developers.cloudflare.com/workers/) and [Workers KV Storage](https://developers.cloudflare.com/kv/api/). |
| Workers Routes Edit | Grants write access to [Cloudflare Workers](https://developers.cloudflare.com/workers/) and [Workers KV Storage](https://developers.cloudflare.com/kv/api/). |
| Zaraz Read | Grants read access to [Zaraz](https://developers.cloudflare.com/zaraz/) zone level settings. |
| Zaraz Edit | Grants write access to [Zaraz](https://developers.cloudflare.com/zaraz/) zone level settings. |
| Zone Read | Grants read access to zone management. |
| Zone Edit | Grants write access to zone management. |
| Zone Security Center Insights | Grants read access to zone level [Security Center Insights](https://developers.cloudflare.com/security/security-insights/). |
| Zone Security Center Insights Edit | Grants write access to zone level [Security Center Zone Insights](https://developers.cloudflare.com/security/security-insights/). |
| Zone Settings Read | Grants read access to zone settings. |
| Zone Settings Edit | Grants write access to zone settings. |
| Zone Versioning Read | Grants read access to [Zone Versioning](https://developers.cloudflare.com/version-management/) at zone level. |
| Zone Versioning Edit | Grants write access to [Zone Versioning](https://developers.cloudflare.com/version-management/) at zone level. |
| Zone WAF Read | Grants read access to [Zone WAF](https://developers.cloudflare.com/waf/). |
| Zone WAF Edit | Grants write access to [Zone WAF](https://developers.cloudflare.com/waf/). |

| Name | Description |
| --- | --- |
| Access: Apps and Policies Read | Grants read access to [Cloudflare Access](https://developers.cloudflare.com/cloudflare-one/access-controls/policies/) zone resources. |
| Access: Apps and Policies Revoke | Grants ability to revoke all tokens to [Cloudflare Access](https://developers.cloudflare.com/cloudflare-one/access-controls/policies/) zone resources. |
| Access: Apps and Policies Write | Grants write access to [Cloudflare Access](https://developers.cloudflare.com/cloudflare-one/access-controls/policies/) zone resources. |
| Analytics Read | Grants read access to [analytics](https://developers.cloudflare.com/analytics/account-and-zone-analytics/zone-analytics/). |
| Domain API Gateway Read | Grants read access to [API Gateway](https://developers.cloudflare.com/api-shield/) zone resources. |
| Domain API Gateway Write | Grants write access to [API Gateway](https://developers.cloudflare.com/api-shield/) zone resources. |
| Apps Write | Grants full access to Cloudflare Apps (deprecated, refer to [Workers](https://developers.cloudflare.com/workers/) instead). |
| Bot Management Read | Grants read access to [Bot Management](https://developers.cloudflare.com/bots/plans/bm-subscription/). |
| Bot Management Write | Grants write access to [Bot Management](https://developers.cloudflare.com/bots/plans/bm-subscription/). |
| Bot Management Feedback Read | Grants read access to [Bot Management feedback](https://developers.cloudflare.com/bots/concepts/feedback-loop/). |
| Bot Management Feedback Write | Grants write access to [Bot Management feedback](https://developers.cloudflare.com/bots/concepts/feedback-loop/). |
| Cache Purge | Grants access to [purge cache](https://developers.cloudflare.com/cache/how-to/purge-cache/). |
| Cache Settings Read | Grants read access to [Cache Rules](https://developers.cloudflare.com/cache/how-to/cache-rules/). |
| Cache Settings Write | Grants write access to [Cache Rules](https://developers.cloudflare.com/cache/how-to/cache-rules/). |
| Cloud Connector Read | Grants read access to [Cloud Connector rules](https://developers.cloudflare.com/rules/cloud-connector/). |
| Cloud Connector Write | Grants write access to [Cloud Connector rules](https://developers.cloudflare.com/rules/cloud-connector/). |
| Config Settings Read | Grants read access to [Configuration Rules](https://developers.cloudflare.com/rules/configuration-rules/). |
| Config Settings Write | Grants write access to [Configuration Rules](https://developers.cloudflare.com/rules/configuration-rules/). |
| Custom Errors Read | Grants read access to [Custom Error Rules](https://developers.cloudflare.com/rules/custom-errors/). |
| Custom Errors Write | Grants write access to [Custom Error Rules](https://developers.cloudflare.com/rules/custom-errors/). |
| Custom Pages Read | Grants read access to [Custom Error Pages](https://developers.cloudflare.com/rules/custom-errors/). |
| Custom Pages Write | Grants write access to [Custom Error Pages](https://developers.cloudflare.com/rules/custom-errors/). |
| Email Security DMARC Reports Read | Grants read access to [DMARC Management](https://developers.cloudflare.com/dmarc-management/). |
| Email Security DMARC Reports Write | Grants write access to [DMARC Management](https://developers.cloudflare.com/dmarc-management/). |
| DNS Read | Grants read access to [DNS](https://developers.cloudflare.com/dns/). |
| DNS Write | Grants write access to [DNS](https://developers.cloudflare.com/dns/). |
| Email Routing Rules Read | Grants read access to [Email Routing Rules](https://developers.cloudflare.com/email-service/configuration/email-routing-addresses/). |
| Email Routing Rules Write | Grants write access to [Email Routing Rules](https://developers.cloudflare.com/email-service/configuration/email-routing-addresses/). |
| Firewall Services Read | Grants read access to Firewall resources. |
| Firewall Services Write | Grants write access to Firewall resources. |
| Health Checks Read | Grants read access to [Health Checks](https://developers.cloudflare.com/health-checks/). |
| Health Checks Write | Grants write access to [Health Checks](https://developers.cloudflare.com/health-checks/). |
| HTTP DDoS Managed Ruleset Read | Grants read access to [HTTP DDoS managed ruleset](https://developers.cloudflare.com/ddos-protection/managed-rulesets/http/). |
| HTTP DDoS Managed Ruleset Write | Grants write access to [HTTP DDoS managed ruleset](https://developers.cloudflare.com/ddos-protection/managed-rulesets/http/). |
| Load Balancers Read | Grants read access to [load balancer resources](https://developers.cloudflare.com/load-balancing/). |
| Load Balancers Write | Grants write access to [load balancer resources](https://developers.cloudflare.com/load-balancing/). |
| Logs Read | Grants read access to logs using [Logpull](https://developers.cloudflare.com/logs/). |
| Logs Write | Grants write access to [Logpull and Logpush](https://developers.cloudflare.com/logs/). |
| Managed headers Read | Grants read access to [Managed Headers](https://developers.cloudflare.com/rules/transform/managed-transforms/). |
| Managed headers Write | Grants write access to [Managed Headers](https://developers.cloudflare.com/rules/transform/managed-transforms/). |
| Origin Read | Grants read access to [Origin Rules](https://developers.cloudflare.com/rules/origin-rules/). |
| Origin Write | Grants write access to [Origin Rules](https://developers.cloudflare.com/rules/origin-rules/). |
| Page Rules Read | Grants read access to [Page Rules](https://developers.cloudflare.com/rules/page-rules/). |
| Page Rules Write | Grants write access to [Page Rules](https://developers.cloudflare.com/rules/page-rules/). |
| Domain Page Shield Read | Grants read access to [client-side security](https://developers.cloudflare.com/client-side-security/) (previously known as Page Shield). |
| Domain Page Shield Write | Grants write access to [client-side security](https://developers.cloudflare.com/client-side-security/) (previously known as Page Shield). |
| Response Compression Read | Grants read access to [Response Compression](https://developers.cloudflare.com/rules/compression-rules/). |
| Response Compression Write | Grants write access to [Response Compression](https://developers.cloudflare.com/rules/compression-rules/). |
| Sanitize Read | Grants read access to sanitization. |
| Sanitize Write | Grants write access to sanitization. |
| Dynamic URL Redirects Read | Grants read access to zone-level [Single Redirects](https://developers.cloudflare.com/rules/url-forwarding/single-redirects/). |
| Dynamic URL Redirects Write | Grants write access to zone-level [Single Redirects](https://developers.cloudflare.com/rules/url-forwarding/single-redirects/). |
| SSL and Certificates Read | Grants read access to [SSL configuration and certificate management](https://developers.cloudflare.com/ssl/). |
| SSL and Certificates Write | Grants write access to [SSL configuration and certificate management](https://developers.cloudflare.com/ssl/). |
| Zone Transform Rules Read | Grants read access to [Transform Rules](https://developers.cloudflare.com/rules/transform/). |
| Zone Transform Rules Write | Grants write access to [Transform Rules](https://developers.cloudflare.com/rules/transform/). |
| Waiting Rooms Read | Grants read access to [Waiting Room](https://developers.cloudflare.com/waiting-room/). |
| Waiting Rooms Write | Grants write access to [Waiting Room](https://developers.cloudflare.com/waiting-room/). |
| Web3 Hostnames Read | Grants read access to [Web3 Hostnames](https://developers.cloudflare.com/web3/). |
| Web3 Hostnames Write | Grants write access to [Web3 Hostnames](https://developers.cloudflare.com/web3/). |
| Workers Routes Read | Grants read access to [Cloudflare Workers](https://developers.cloudflare.com/workers/) and [Workers KV Storage](https://developers.cloudflare.com/kv/api/). |
| Workers Routes Write | Grants write access to [Cloudflare Workers](https://developers.cloudflare.com/workers/) and [Workers KV Storage](https://developers.cloudflare.com/kv/api/). |
| Zaraz Read | Grants read access to [Zaraz](https://developers.cloudflare.com/zaraz/) zone level settings. |
| Zaraz Write | Grants write access to [Zaraz](https://developers.cloudflare.com/zaraz/) zone level settings. |
| Zone Read | Grants read access to zone management. |
| Zone Write | Grants write access to zone management. |
| Zone Security Center Insights | Grants read access to zone level [Security Center Insights](https://developers.cloudflare.com/security/security-insights/). |
| Zone Security Center Insights Write | Grants write access to zone level [Security Center Zone Insights](https://developers.cloudflare.com/security/security-insights/). |
| Zone Settings Read | Grants read access to zone settings. |
| Zone Settings Write | Grants write access to zone settings. |
| Zone Versioning Read | Grants read access to [Zone Versioning](https://developers.cloudflare.com/version-management/) at zone level. |
| Zone Versioning Write | Grants write access to [Zone Versioning](https://developers.cloudflare.com/version-management/) at zone level. |
| Zone WAF Read | Grants read access to [Zone WAF](https://developers.cloudflare.com/waf/). |
| Zone WAF Write | Grants write access to [Zone WAF](https://developers.cloudflare.com/waf/). |

Was this helpful?

YesNo

## On this page

[![](https://developers.cloudflare.com/_astro/logo.te5VL_aD.svg)Docs](https://developers.cloudflare.com/)

```json
{"@context":"https://schema.org","@type":"TechArticle","@id":"https://developers.cloudflare.com/fundamentals/api/reference/permissions/#page","headline":"API token permissions","description":"Review available Cloudflare API token permissions for user, account, and zone resources.","url":"https://developers.cloudflare.com/fundamentals/api/reference/permissions/","inLanguage":"en","image":"https://developers.cloudflare.com/fundamentals/api/reference/permissions/og.png?v=d5142d1f6e167ad8","dateModified":"2026-09-16","publisher":{"@type":"Organization","name":"Cloudflare","description":"One platform for your apps, agents, and workforce. Build, secure, and scale without managing infrastructure","url":"https://www.cloudflare.com/","sameAs":["https://github.com/cloudflare","https://www.linkedin.com/company/cloudflare","https://x.com/cloudflare"],"logo":{"@type":"ImageObject","url":"https://developers.cloudflare.com/logo.svg"},"address":{"@type":"PostalAddress","streetAddress":"101 Townsend St","addressLocality":"San Francisco","addressRegion":"CA","postalCode":"94107","addressCountry":"US"},"contactPoint":[{"@type":"ContactPoint","contactType":"Customer Support","url":"https://support.cloudflare.com/","availableLanguage":["English"]},{"@type":"ContactPoint","contactType":"Sales","url":"https://www.cloudflare.com/contact/","availableLanguage":["English"]}]},"isPartOf":{"@type":"WebSite","@id":"https://developers.cloudflare.com/#website","name":"Cloudflare Docs","url":"https://developers.cloudflare.com/"}}
```
