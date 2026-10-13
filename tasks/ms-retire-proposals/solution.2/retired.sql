-- Run before the migration that retires citizen proposals: the columns other
-- tables kept about proposals and the rows about the retired records that the
-- migration deletes go under db/retired as CSV. pg_dump takes the tables.
\set ON_ERROR_STOP on

-- The retired columns.
\copy (SELECT id, proposal_id FROM poll_questions WHERE proposal_id IS NOT NULL ORDER BY id) TO 'db/retired/poll_questions_proposal_id.csv' CSV HEADER
\copy (SELECT id, proposal_id FROM map_locations WHERE proposal_id IS NOT NULL ORDER BY id) TO 'db/retired/map_locations_proposal_id.csv' CSV HEADER
\copy (SELECT id, name, proposals_count FROM tags WHERE proposals_count > 0 ORDER BY id) TO 'db/retired/tags_proposals_count.csv' CSV HEADER
\copy (SELECT id, recommended_proposals, email_digest, failed_email_digests_count FROM users ORDER BY id) TO 'db/retired/users_proposal_preferences.csv' CSV HEADER

-- The rows other tables hold about the retired records, selected as the
-- migration deletes them: the rows naming a retired class, the comments on
-- the retired records with whatever points at those comments, and the
-- communities of proposals with their topics.
CREATE TEMP TABLE retired_types (type) AS VALUES ('Proposal'), ('ProposalNotification'), ('Dashboard::Action');
CREATE TEMP VIEW retired_communities AS SELECT community_id AS id FROM proposals WHERE community_id IS NOT NULL;
CREATE TEMP VIEW retired_topics AS SELECT id FROM topics WHERE community_id IN (SELECT id FROM retired_communities);
CREATE TEMP VIEW retired_comments AS SELECT id FROM comments WHERE commentable_type IN (SELECT type FROM retired_types) OR (commentable_type = 'Topic' AND commentable_id IN (SELECT id FROM retired_topics));

\copy (SELECT * FROM votes WHERE votable_type IN (SELECT type FROM retired_types) OR (votable_type = 'Comment' AND votable_id IN (SELECT id FROM retired_comments)) ORDER BY id) TO 'db/retired/leftover_votes.csv' CSV HEADER
\copy (SELECT * FROM flags WHERE flaggable_type IN (SELECT type FROM retired_types) OR (flaggable_type = 'Comment' AND flaggable_id IN (SELECT id FROM retired_comments)) ORDER BY id) TO 'db/retired/leftover_flags.csv' CSV HEADER
\copy (SELECT * FROM notifications WHERE notifiable_type IN (SELECT type FROM retired_types) OR (notifiable_type = 'Comment' AND notifiable_id IN (SELECT id FROM retired_comments)) ORDER BY id) TO 'db/retired/leftover_notifications.csv' CSV HEADER
\copy (SELECT * FROM activities WHERE actionable_type IN (SELECT type FROM retired_types) OR (actionable_type = 'Comment' AND actionable_id IN (SELECT id FROM retired_comments)) ORDER BY id) TO 'db/retired/leftover_activities.csv' CSV HEADER
\copy (SELECT * FROM comment_translations WHERE comment_id IN (SELECT id FROM retired_comments) ORDER BY id) TO 'db/retired/leftover_comment_translations.csv' CSV HEADER
\copy (SELECT * FROM comments WHERE id IN (SELECT id FROM retired_comments) ORDER BY id) TO 'db/retired/leftover_comments.csv' CSV HEADER
\copy (SELECT * FROM ml_summary_comments WHERE commentable_type IN (SELECT type FROM retired_types) ORDER BY id) TO 'db/retired/leftover_ml_summary_comments.csv' CSV HEADER
\copy (SELECT * FROM follows WHERE followable_type IN (SELECT type FROM retired_types) ORDER BY id) TO 'db/retired/leftover_follows.csv' CSV HEADER
\copy (SELECT * FROM taggings WHERE taggable_type IN (SELECT type FROM retired_types) ORDER BY id) TO 'db/retired/leftover_taggings.csv' CSV HEADER
\copy (SELECT * FROM active_storage_attachments WHERE (record_type = 'Image' AND record_id IN (SELECT id FROM images WHERE imageable_type IN (SELECT type FROM retired_types))) OR (record_type = 'Document' AND record_id IN (SELECT id FROM documents WHERE documentable_type IN (SELECT type FROM retired_types))) ORDER BY id) TO 'db/retired/leftover_active_storage_attachments.csv' CSV HEADER
\copy (SELECT * FROM images WHERE imageable_type IN (SELECT type FROM retired_types) ORDER BY id) TO 'db/retired/leftover_images.csv' CSV HEADER
\copy (SELECT * FROM documents WHERE documentable_type IN (SELECT type FROM retired_types) ORDER BY id) TO 'db/retired/leftover_documents.csv' CSV HEADER
\copy (SELECT * FROM milestone_translations WHERE milestone_id IN (SELECT id FROM milestones WHERE milestoneable_type IN (SELECT type FROM retired_types)) ORDER BY id) TO 'db/retired/leftover_milestone_translations.csv' CSV HEADER
\copy (SELECT * FROM milestones WHERE milestoneable_type IN (SELECT type FROM retired_types) ORDER BY id) TO 'db/retired/leftover_milestones.csv' CSV HEADER
\copy (SELECT * FROM progress_bar_translations WHERE progress_bar_id IN (SELECT id FROM progress_bars WHERE progressable_type IN (SELECT type FROM retired_types)) ORDER BY id) TO 'db/retired/leftover_progress_bar_translations.csv' CSV HEADER
\copy (SELECT * FROM progress_bars WHERE progressable_type IN (SELECT type FROM retired_types) ORDER BY id) TO 'db/retired/leftover_progress_bars.csv' CSV HEADER
\copy (SELECT * FROM remote_translations WHERE remote_translatable_type IN (SELECT type FROM retired_types) ORDER BY id) TO 'db/retired/leftover_remote_translations.csv' CSV HEADER
\copy (SELECT * FROM sdg_relations WHERE relatable_type IN (SELECT type FROM retired_types) ORDER BY id) TO 'db/retired/leftover_sdg_relations.csv' CSV HEADER
\copy (SELECT * FROM sdg_reviews WHERE relatable_type IN (SELECT type FROM retired_types) ORDER BY id) TO 'db/retired/leftover_sdg_reviews.csv' CSV HEADER
\copy (SELECT * FROM signatures WHERE signature_sheet_id IN (SELECT id FROM signature_sheets WHERE signable_type IN (SELECT type FROM retired_types)) ORDER BY id) TO 'db/retired/leftover_signatures.csv' CSV HEADER
\copy (SELECT * FROM signature_sheets WHERE signable_type IN (SELECT type FROM retired_types) ORDER BY id) TO 'db/retired/leftover_signature_sheets.csv' CSV HEADER
\copy (SELECT * FROM related_content_scores WHERE related_content_id IN (SELECT id FROM related_contents WHERE parent_relationable_type IN (SELECT type FROM retired_types) OR child_relationable_type IN (SELECT type FROM retired_types)) ORDER BY id) TO 'db/retired/leftover_related_content_scores.csv' CSV HEADER
\copy (SELECT * FROM related_contents WHERE parent_relationable_type IN (SELECT type FROM retired_types) OR child_relationable_type IN (SELECT type FROM retired_types) ORDER BY id) TO 'db/retired/leftover_related_contents.csv' CSV HEADER
\copy (SELECT * FROM topics WHERE community_id IN (SELECT id FROM retired_communities) ORDER BY id) TO 'db/retired/leftover_topics.csv' CSV HEADER
\copy (SELECT * FROM communities WHERE id IN (SELECT id FROM retired_communities) ORDER BY id) TO 'db/retired/leftover_communities.csv' CSV HEADER
\copy (SELECT * FROM map_locations WHERE proposal_id IS NOT NULL ORDER BY id) TO 'db/retired/leftover_map_locations.csv' CSV HEADER
