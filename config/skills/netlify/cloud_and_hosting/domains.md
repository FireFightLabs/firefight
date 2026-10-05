---
name: netlify_domains
when: A Netlify site does not answer at its custom domain, answers at the wrong one, or its HTTPS fails, while it works at its netlify.app address
tools: [resource_status, list_sites]
---
1. Call `resource_status` for the site's custom domain, its aliases, whether HTTPS is on and forced, and whether its DNS is on Netlify or elsewhere.
2. When the domain is missing from the site, it was never added to it or it sits on another site. Call `list_sites`, which names each site's custom domain, and look for it there.
3. When DNS is elsewhere, the records at the domain's DNS provider must point at the site as Netlify's domain settings give them. A subdomain such as www takes a CNAME record. An apex domain cannot take a CNAME, so it takes an ALIAS, ANAME, flattened CNAME or A record, whichever the provider supports. Adding an apex domain or its www subdomain to a site adds the other too, so both need records. If the domain is on the resource map with its DNS provider, read that provider's records for it.
4. When HTTPS is off or failing, Netlify issues its certificate only once the domain's DNS points at Netlify and older records' TTLs have run out. A service in front of the site that ends TLS itself, such as a proxying CDN, stops the certificate being issued until that routing is turned off. The certificate's state is on the site's domain settings in Netlify.
5. Say what the domain points at, what it should point at, and who has to change it.
