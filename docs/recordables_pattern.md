# The Rails Delegated Type Pattern: Recordings, Recordables, and Events

Based on the 37signals article: https://dev.37signals.com/the-rails-delegated-type-pattern/

## Core Architecture

**Recordings (the primary table):**
- Stores common metadata across all content types (timestamps, creator ID, parent relationships)
- Contains `recordable_type` and `recordable_id` columns that reference the specific content
- Stays lean and lightweight, enabling efficient querying and pagination
- Forms a tree structure (messages contain comments, comments contain attachments)

**Recordables (specialized tables):**
- Separate tables for each content type: `messages`, `documents`, `comments`, `uploads`
- Contain only type-specific data (e.g., message has just title and content)
- **Immutable by design** - never edited in place

**Events (change tracking table):**
- Logs every recordable change over time
- References both the recording AND the specific recordable at that moment
- Enables viewing historical versions of content

## How Changes Are Tracked

1. **Create new recordable instead of editing:** When content changes, a new recordable row is created
2. **Update recording pointer:** The recording's `recordable_id` updates to reference the new version
3. **Log event:** An event row captures this change, linking the recording to the new recordable
4. **History preserved:** Old recordables remain unchanged, creating an automatic version history

## Key Benefits

- **Complete audit trail** without explicit version tracking logic
- **Efficient copying** - multiple recordings can point to the same recordable
- **Easy rollback** - just update the recording to point to an older recordable
- **Unified querying** - query all content types from one table
- **No migrations needed** when adding new content types

## Design Principles

### Immutable Recordables
Recordables are never modified in place. Instead, new recordables are created for each change, enabling:
- Complete version history without additional tracking
- Efficient copying (multiple recordings can reference the same recordable)
- Easy rollback to previous states

### Tree Structure
Recordings organize hierarchically:
- Message boards contain messages
- Messages contain comments
- Comments can contain attachments

Only recordings can have parent-child relationships; recordables exist independently.

### Event Tracking
A separate events table logs every recordable change:
- Events reference both a recording and its associated recordable at a specific moment
- Enables accurate historical timelines showing what content looked like at any time
- Supports features like "make this the current version" by updating the recording's pointer

## Implementation Benefits

### Scalability Without Migration Penalties
Adding new content types requires only:
- Creating a new recordable table
- Recording rows reference it via the delegated type mechanism
- The recordings table itself never changes

This contrasts sharply with single-table inheritance, where each new type adds columns to the main table.

### Unified Querying
Timeline features querying across content types in a single operation:

```ruby
recordings.where(
  recordable_type: ['Message', 'Document', 'Comment']
).order(created_at: :desc).limit(50)
```

This pagination works efficiently because recordings are lightweight, lacking text columns.

### Composable Features
Recording-level capabilities work across all types:
- **Commentable**: Any recording type can opt in via defining a method
- **Copyable**: Generic copier passes message to recordable; each type implements its own logic
- **Exportable**: Recording delegates export format to its recordable
- **Cacheable**: Cache keys use only recording references; invalidation works uniformly

### Mobile and API Efficiency
A single JSON API serves all content types. Adding new recordables requires no mobile app releases; the app handles unknown types generically by accessing standard recording properties.

## Performance Characteristics

### Database Efficiency
- Recordings table remains lean despite billions of rows
- Indexing lightweight foreign key references is inexpensive
- Content stays distributed across specialized tables, avoiding massive table bloat

### Caching Strategy
All views use a uniform pattern: `cache (recording) do...end`

This "Russian doll" caching allows deep-tree changes to invalidate only affected branches while parents remain cached.

### Copying Efficiency
Rather than duplicating content, copying creates a new recording pointing to the existing recordable. With thousands of Basecamp accounts sharing demo projects, this prevents massive duplication.

## When to Use This Pattern

**Ideal for:**
- Content management systems
- Wiki-like applications
- Collaboration platforms where diverse content types share common operations
- Systems prioritizing feature velocity over individual type richness

**Less suitable for:**
- Highly specialized domain models
- Applications where types have minimal behavioral overlap
- Systems requiring frequent type-specific logic

The pattern succeeds when the common case—adding new content types, copying, moving, exporting—outweighs the cost of generic abstraction.

---

*Note: The pattern prioritizes feature velocity and scalability over model richness, which is why Basecamp has used it successfully for over 10 years.*
