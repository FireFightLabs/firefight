---
name: declaring
when: Declaring a new incident, including one for something already found in this chat
tools: [get_form, declare_incident]
---
1. Call `get_form` with `form` set to declare. It lists every field this workspace asks, which are required, and the choices for each one. Do not call anything else to find the severities or types, since the form already lists them.
2. Fill the fields from what the person said and what this chat already found. `name` is a short title of what is broken, as a responder would say it. `summary` is what is known so far, in a sentence or two.
3. Answer only the fields the form lists as asked, keyed exactly as it names them. Leave out a field marked asked false.
4. A choice takes one of the values the form lists. When the person's words fit more than one, ask which, naming them. When a required field has no answer and nothing said points to one, ask for that field alone.
5. Call `declare_incident` with the `answers`. Say the identifier it returns.
