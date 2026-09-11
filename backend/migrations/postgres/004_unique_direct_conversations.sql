-- Un chat sin producto ni "se busca" representa a una pareja, no una
-- dirección buyer/seller. Antes dos solicitudes simultáneas podían observar
-- "no existe" y crear dos hilos invertidos. Consolidamos cualquier duplicado
-- histórico antes de imponer la unicidad simétrica.

CREATE TEMP TABLE direct_conversation_merge_map (
  duplicate_id TEXT PRIMARY KEY,
  keep_id TEXT NOT NULL
) ON COMMIT DROP;

INSERT INTO direct_conversation_merge_map (duplicate_id, keep_id)
WITH ranked AS (
  SELECT
    id,
    FIRST_VALUE(id) OVER (
      PARTITION BY LEAST(buyer_id, seller_id), GREATEST(buyer_id, seller_id)
      ORDER BY created_at ASC, id ASC
    ) AS keep_id,
    ROW_NUMBER() OVER (
      PARTITION BY LEAST(buyer_id, seller_id), GREATEST(buyer_id, seller_id)
      ORDER BY created_at ASC, id ASC
    ) AS position
  FROM conversations
  WHERE product_id IS NULL AND wanted_post_id IS NULL
)
SELECT id, keep_id
FROM ranked
WHERE position > 1;

-- Los ids de mensaje permanecen estables, por lo que respuestas y cortes de
-- historial siguen apuntando al mismo contenido después de moverlo al hilo
-- ganador.
UPDATE messages AS message
SET conversation_id = merge.keep_id
FROM direct_conversation_merge_map AS merge
WHERE message.conversation_id = merge.duplicate_id;

-- Puede existir un corte de historial para la misma persona en varios hilos.
-- `deleted_at` no indica qué tanto historial se ocultó: una acción posterior
-- sobre un hilo viejo podría apuntar a un mensaje anterior. Se conserva el
-- mensaje con mayor seq dentro del historial ya reunido para no resucitar
-- contenido que la persona había eliminado.
CREATE TEMP TABLE direct_conversation_deletion_winners
ON COMMIT DROP
AS
WITH source_conversations AS (
  SELECT duplicate_id AS source_id, keep_id
  FROM direct_conversation_merge_map
  UNION ALL
  SELECT DISTINCT keep_id AS source_id, keep_id
  FROM direct_conversation_merge_map
)
SELECT DISTINCT ON (source.keep_id, deletion.user_id)
  source.keep_id AS conversation_id,
  deletion.user_id,
  deletion.deleted_through_message_id,
  deletion.deleted_at
FROM source_conversations AS source
JOIN conversation_deletions AS deletion
  ON deletion.conversation_id = source.source_id
LEFT JOIN messages AS cutoff
  ON cutoff.id = deletion.deleted_through_message_id
ORDER BY
  source.keep_id,
  deletion.user_id,
  COALESCE(cutoff.seq, 0) DESC,
  deletion.deleted_at DESC,
  deletion.conversation_id ASC;

DELETE FROM conversation_deletions AS deletion
USING direct_conversation_merge_map AS merge
WHERE deletion.conversation_id = merge.duplicate_id;

INSERT INTO conversation_deletions (
  conversation_id,
  user_id,
  deleted_through_message_id,
  deleted_at
)
SELECT conversation_id, user_id, deleted_through_message_id, deleted_at
FROM direct_conversation_deletion_winners
ON CONFLICT (conversation_id, user_id) DO UPDATE
SET
  deleted_through_message_id = EXCLUDED.deleted_through_message_id,
  deleted_at = EXCLUDED.deleted_at;

-- Un reporte de chat debe seguir abriendo el hilo que sobrevivió.
UPDATE reports AS report
SET target_id = merge.keep_id
FROM direct_conversation_merge_map AS merge
WHERE report.target_type = 'chat'
  AND report.target_id = merge.duplicate_id;

-- Conserva operativos los deep-links y el marcado de notificaciones. `data`
-- es TEXT por compatibilidad legacy, por eso el CASE valida JSON antes del
-- cast y deja intacta cualquier fila histórica malformada.
WITH parsed_notifications AS MATERIALIZED (
  SELECT
    id,
    CASE WHEN data IS JSON THEN data::jsonb ELSE NULL END AS payload
  FROM notifications
)
UPDATE notifications AS notification
SET data = jsonb_set(
  parsed.payload,
  '{conversationId}',
  to_jsonb(merge.keep_id),
  false
)::text
FROM parsed_notifications AS parsed
JOIN direct_conversation_merge_map AS merge
  ON parsed.payload ->> 'conversationId' = merge.duplicate_id
WHERE notification.id = parsed.id;

-- Recalcula la vista previa después de reunir mensajes que antes estaban en
-- hilos distintos.
WITH affected AS (
  SELECT DISTINCT keep_id FROM direct_conversation_merge_map
), latest AS (
  SELECT DISTINCT ON (message.conversation_id)
    message.conversation_id,
    message.created_at,
    CASE WHEN message.image_url IS NOT NULL THEN '📷 Foto' ELSE message.text END AS preview
  FROM messages AS message
  JOIN affected ON affected.keep_id = message.conversation_id
  ORDER BY message.conversation_id, message.created_at DESC, message.seq DESC
)
UPDATE conversations AS conversation
SET
  last_message_at = latest.created_at,
  last_message_preview = latest.preview
FROM latest
WHERE conversation.id = latest.conversation_id;

DELETE FROM conversations AS conversation
USING direct_conversation_merge_map AS merge
WHERE conversation.id = merge.duplicate_id;

CREATE UNIQUE INDEX idx_conversations_direct_pair_unique
  ON conversations (
    LEAST(buyer_id, seller_id),
    GREATEST(buyer_id, seller_id)
  )
  WHERE product_id IS NULL AND wanted_post_id IS NULL;
