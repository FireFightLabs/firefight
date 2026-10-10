---
name: digitalocean_cost
when: Watching or explaining what the DigitalOcean account spends, a bill that grew, or which product costs more than before
tools: [billing, list_resources, describe_resource]
signals: [cost]
---
1. Read the account's spend with `billing`: used this month so far, the month so far by product, and each month before. Pass `months` for a longer view.
2. Project this month from its days so far and compare it with the months before.
3. Find the product that grew, such as Droplets, Managed Databases or App Platform, then what runs in it with `list_resources` and `describe_resource`: new or larger Droplets, more app instances, a larger database.
4. DigitalOcean refusing the read means the token lacks the billing:read scope. Say so, and that an admin gives the token that scope.
