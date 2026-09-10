-- Marketplace UM: esquema base para PostgreSQL 16+
-- Generado desde el esquema SQLite final; no editar después de aplicarlo.
SET TIME ZONE 'UTC';

CREATE TABLE admins (
      id BIGSERIAL PRIMARY KEY,
      username TEXT NOT NULL  UNIQUE
        CHECK(length(username) BETWEEN 3 AND 64),
      password_hash TEXT NOT NULL,
      totp_secret_encrypted TEXT NOT NULL,
      active INTEGER NOT NULL DEFAULT 1 CHECK(active IN (0, 1)),
      token_version INTEGER NOT NULL DEFAULT 0,
      last_totp_step INTEGER,
      last_login_at TIMESTAMPTZ,
      created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
    );

CREATE TABLE cart (
      id TEXT PRIMARY KEY,
      productId TEXT NOT NULL,
      quantity INTEGER DEFAULT 1,
      meetingPoint TEXT DEFAULT 'Por definir'
    , user_id TEXT);

CREATE TABLE categories (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      emoji TEXT,
      icon TEXT,
      color TEXT
    );

CREATE TABLE category_engagement_events (
      id          BIGSERIAL PRIMARY KEY,
      category_id TEXT NOT NULL,
      event_type  TEXT NOT NULL CHECK(event_type IN ('publish', 'icon_tap', 'product_view')),
      created_at  TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
    );

CREATE TABLE category_interests (
      id BIGSERIAL PRIMARY KEY,
      user_id TEXT NOT NULL,
      category_id TEXT NOT NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
      UNIQUE(user_id, category_id)
    );

CREATE TABLE chat_user_settings (
      owner_id TEXT NOT NULL,
      target_id TEXT NOT NULL,
      blocked INTEGER NOT NULL DEFAULT 0,
      muted INTEGER NOT NULL DEFAULT 0,
      updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (owner_id, target_id),
      CHECK(owner_id <> target_id)
    );

CREATE TABLE conversations (
        id TEXT PRIMARY KEY,
        product_id TEXT,
        wanted_post_id TEXT,
        buyer_id TEXT NOT NULL,
        seller_id TEXT NOT NULL,
        created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        last_message_at TIMESTAMPTZ,
        last_message_preview TEXT DEFAULT ''
      );

CREATE TABLE highlight_plans (
      id TEXT PRIMARY KEY,
      title TEXT,
      price TEXT,
      description TEXT,
      days INTEGER
    );

CREATE TABLE interest_notification_queue (
      product_id   TEXT PRIMARY KEY,
      created_at   TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
      processed_at TIMESTAMPTZ
    );

CREATE TABLE listings (
      id TEXT PRIMARY KEY,
      productId TEXT NOT NULL
    );

CREATE TABLE mp_webhook_events (
      id BIGSERIAL PRIMARY KEY,
      event_id TEXT NOT NULL UNIQUE,
      topic TEXT,
      resource_id TEXT,
      received_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
      processed_at TIMESTAMPTZ
    );

CREATE TABLE notification_log (
      id              BIGSERIAL PRIMARY KEY,
      subject_id      TEXT NOT NULL,
      type            TEXT NOT NULL,
      category_id     TEXT,
      product_ids     TEXT NOT NULL DEFAULT '[]',
      notification_id TEXT,
      sent_at         TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
      opened_at       TIMESTAMPTZ
    );

CREATE TABLE notifications (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      type TEXT NOT NULL,
      title TEXT NOT NULL,
      body TEXT NOT NULL,
      data TEXT DEFAULT '{}',
      read INTEGER NOT NULL DEFAULT 0,
      created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
    );

CREATE TABLE price_history (
      id BIGSERIAL PRIMARY KEY,
      product_id TEXT NOT NULL,
      price DOUBLE PRECISION NOT NULL,
      changed_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
    );

CREATE TABLE profile_view_events (
      profile_id TEXT NOT NULL,
      viewer_key TEXT NOT NULL,
      viewed_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (profile_id, viewer_key)
    );

CREATE TABLE push_tokens (
      id BIGSERIAL PRIMARY KEY,
      user_id TEXT NOT NULL,
      player_id TEXT NOT NULL,
      platform TEXT DEFAULT 'unknown',
      created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
      UNIQUE(user_id, player_id)
    );

CREATE TABLE refresh_sessions (
      token_hash TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
      last_used_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
      revoked_at TIMESTAMPTZ
    );

CREATE TABLE revoked_sessions (
      jti TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      expires_at INTEGER NOT NULL,
      revoked_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
    );

CREATE TABLE search_queries (
      id BIGSERIAL PRIMARY KEY,
      query_text TEXT NOT NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
    , query_key TEXT, device_id TEXT);

CREATE TABLE secret_solves (
      user_id   TEXT PRIMARY KEY,
      posicion  INTEGER NOT NULL,
      solved_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
    );

CREATE TABLE sellers (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      email TEXT,
      phone TEXT,
      avatarInitials TEXT,
      major TEXT,
      isBusiness INTEGER DEFAULT 0,
      logoUrl TEXT,
      rating DOUBLE PRECISION DEFAULT 0,
      reviews INTEGER DEFAULT 0,
      verified INTEGER DEFAULT 0
    , businessDescription TEXT, businessCategory TEXT, password_hash TEXT, failed_login_attempts INTEGER DEFAULT 0, locked_until TIMESTAMPTZ, businessHours TEXT, location_lat DOUBLE PRECISION, location_lng DOUBLE PRECISION, paymentMethods TEXT, tipo_cuenta TEXT, carrera TEXT, tipo_verificacion TEXT, colorAcento TEXT, producto_fijado_id TEXT, median_response_minutes INTEGER, facebook_url TEXT, instagram_url TEXT, whatsapp_number TEXT, tiktok_url TEXT, twitter_url TEXT, last_active TIMESTAMPTZ, show_online_status INTEGER NOT NULL DEFAULT 1, auth_provider TEXT NOT NULL DEFAULT 'password', google_sub TEXT, avatarUrl TEXT, socio_fundador INTEGER DEFAULT 0, created_at TIMESTAMPTZ, insignias_ocultas TEXT, profile_views INTEGER NOT NULL DEFAULT 0, admin_status TEXT NOT NULL DEFAULT 'active'
        CHECK(admin_status IN ('active', 'suspended', 'banned')), admin_status_reason TEXT, admin_status_until TIMESTAMPTZ, auth_invalid_before INTEGER NOT NULL DEFAULT 0
        CHECK(auth_invalid_before >= 0), deleted_at TIMESTAMPTZ);

CREATE TABLE user_category_interest (
      subject_id          TEXT NOT NULL,
      category_id         TEXT NOT NULL,
      interest_score      DOUBLE PRECISION NOT NULL,
      last_interaction_at TIMESTAMPTZ NOT NULL,
      decay_status        TEXT NOT NULL CHECK(decay_status IN ('fresh', 'decaying')),
      updated_at          TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (subject_id, category_id)
    );

CREATE TABLE user_notification_preferences (
      subject_id        TEXT NOT NULL,
      notification_type TEXT NOT NULL,
      enabled           INTEGER NOT NULL DEFAULT 1,
      updated_at        TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (subject_id, notification_type)
    );

CREATE TABLE verification_admin_log (
      id BIGSERIAL PRIMARY KEY,
      request_id TEXT NOT NULL UNIQUE,
      usuario_id TEXT NOT NULL,
      account_name TEXT NOT NULL,
      account_type TEXT NOT NULL
        CHECK(account_type IN ('negocio','estudiante','empleado')),
      action TEXT NOT NULL CHECK(action IN ('verified','unverified')),
      previous_verified INTEGER NOT NULL CHECK(previous_verified IN (0,1)),
      new_verified INTEGER NOT NULL CHECK(new_verified IN (0,1)),
      reason TEXT NOT NULL CHECK(length(reason) BETWEEN 10 AND 500),
      actor TEXT NOT NULL,
      decided_at TIMESTAMPTZ NOT NULL
    );

CREATE TABLE verification_review_log (
      id BIGSERIAL PRIMARY KEY,
      usuario_id TEXT NOT NULL,
      accion TEXT NOT NULL CHECK(accion IN ('approved','rejected','revoked','restored')),
      motivo TEXT,
      nombre_negocio TEXT NOT NULL,
      categoria_negocio TEXT,
      responsable_negocio TEXT,
      decidido_en TIMESTAMPTZ NOT NULL,
      solicitud_json TEXT
    );

CREATE TABLE admin_audit_log (
      id BIGSERIAL PRIMARY KEY,
      admin_id BIGINT NOT NULL,
      action TEXT NOT NULL,
      entity_type TEXT NOT NULL,
      entity_id TEXT NOT NULL,
      details_json TEXT NOT NULL DEFAULT '{}',
      created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY (admin_id) REFERENCES admins(id) ON DELETE RESTRICT
    );

CREATE TABLE admin_revoked_tokens (
      jti TEXT PRIMARY KEY,
      admin_id BIGINT NOT NULL,
      expires_at INTEGER NOT NULL,
      revoked_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY (admin_id) REFERENCES admins(id) ON DELETE CASCADE
    );

CREATE TABLE buyer_mp_customers (
        id BIGSERIAL PRIMARY KEY,
        seller_id TEXT NOT NULL REFERENCES sellers(id) ON DELETE CASCADE,
        vendor_id TEXT NOT NULL REFERENCES sellers(id) ON DELETE CASCADE,
        mp_customer_id TEXT NOT NULL,
        created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        UNIQUE(seller_id, vendor_id)
      );

CREATE TABLE config (
      key TEXT PRIMARY KEY CHECK(key IN (
        'negocio_verificado',
        'negocio_sin_verificar',
        'um_verificado',
        'um_sin_verificar',
        'externo'
      )),
      products_active INTEGER NOT NULL
        CHECK(products_active BETWEEN 0
          AND 1000),
      products_daily INTEGER NOT NULL
        CHECK(products_daily BETWEEN 0
          AND 100),
      wanted_active INTEGER NOT NULL
        CHECK(wanted_active BETWEEN 0
          AND 500),
      wanted_daily INTEGER NOT NULL
        CHECK(wanted_daily BETWEEN 0
          AND 100),
      duration_days INTEGER NOT NULL
        CHECK(duration_days BETWEEN 1
          AND 365),
      updated_by_admin_id BIGINT,
      updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY (updated_by_admin_id) REFERENCES admins(id) ON DELETE SET NULL
    );

CREATE TABLE conversation_deletions (
      conversation_id TEXT NOT NULL,
      user_id TEXT NOT NULL,
      deleted_through_message_id TEXT DEFAULT NULL,
      deleted_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (conversation_id, user_id),
      FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
    );

CREATE TABLE insignias_otorgadas (
      seller_id   TEXT NOT NULL,
      clave       TEXT NOT NULL,
      otorgada_en TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (seller_id, clave),
      FOREIGN KEY (seller_id) REFERENCES sellers(id) ON DELETE CASCADE
    );

CREATE TABLE messages (
        id TEXT PRIMARY KEY,
        seq BIGSERIAL NOT NULL UNIQUE,
        conversation_id TEXT NOT NULL,
        sender_id TEXT NOT NULL,
        text TEXT NOT NULL,
        created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        read INTEGER NOT NULL DEFAULT 0, image_url TEXT DEFAULT NULL, reply_to_message_id TEXT DEFAULT NULL
        REFERENCES messages(id) ON DELETE SET NULL,
        FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
      );

CREATE TABLE orders (
            id TEXT PRIMARY KEY,
            buyer_id TEXT NOT NULL REFERENCES sellers(id) ON DELETE CASCADE,
            vendor_id TEXT NOT NULL REFERENCES sellers(id) ON DELETE CASCADE,
            amount DOUBLE PRECISION NOT NULL,
            application_fee DOUBLE PRECISION NOT NULL DEFAULT 0,
            currency TEXT NOT NULL DEFAULT 'MXN',
            status TEXT NOT NULL DEFAULT 'pending'
              CHECK(status IN ('pending','paid','cancelled','requires_other_method')),
            payment_status TEXT
              CHECK(payment_status IS NULL OR payment_status IN
                ('pending','in_process','approved','authorized','in_mediation',
                 'rejected','refunded','cancelled','charged_back')),
            payment_method TEXT
              CHECK(payment_method IS NULL OR payment_method IN
                ('efectivo','paypal','cripto','tarjeta')),
            mp_payment_id TEXT UNIQUE,
            origin TEXT NOT NULL DEFAULT 'direct' CHECK(origin IN ('direct','cart')),
            created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
          , mp_preference_id TEXT, mp_preference_init_point TEXT, mp_preference_expires_at TIMESTAMPTZ);

CREATE TABLE payment_oauth_states (
      state TEXT PRIMARY KEY,
      seller_id TEXT NOT NULL REFERENCES sellers(id) ON DELETE CASCADE,
      created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
      used_at TIMESTAMPTZ
    );

CREATE TABLE products (
      id TEXT PRIMARY KEY,
      title TEXT NOT NULL,
      price TEXT NOT NULL DEFAULT '0',
      category TEXT,
      description TEXT,
      publishedAgo TEXT,
      seller TEXT,
      images TEXT DEFAULT '[]',
      imageIcon TEXT,
      imageColor TEXT,
      previousPrice TEXT,
      discountLabel TEXT,
      isFeatured INTEGER DEFAULT 0,
      isOffer INTEGER DEFAULT 0,
      isFavorite INTEGER DEFAULT 0,
      status TEXT DEFAULT NULL,
      priceNum DOUBLE PRECISION DEFAULT 0,
      offerExpiresAt TIMESTAMPTZ DEFAULT NULL,
      extras TEXT DEFAULT '[]',
      stock_quantity INTEGER,
      stock_reset_daily INTEGER DEFAULT 0,
      stock_initial INTEGER,
      stock_updated_at TIMESTAMPTZ
    , created_at TIMESTAMPTZ, availableDays TEXT DEFAULT '[]', updated_at TIMESTAMPTZ, location_lat DOUBLE PRECISION, location_lng DOUBLE PRECISION, paymentMethods TEXT DEFAULT NULL, manual_status TEXT DEFAULT NULL, views INTEGER DEFAULT 0, atributos_categoria TEXT DEFAULT NULL, expires_at TIMESTAMPTZ DEFAULT NULL, moderation_status TEXT NOT NULL DEFAULT 'visible'
      CHECK(moderation_status IN ('visible', 'removed', 'spam')), moderation_reason TEXT, moderated_at TIMESTAMPTZ, moderated_by_admin_id BIGINT REFERENCES admins(id));

CREATE TABLE publication_limit_resets (
      user_id TEXT PRIMARY KEY,
      products_reset_at TIMESTAMPTZ,
      wanted_reset_at TIMESTAMPTZ,
      updated_by_admin_id BIGINT NOT NULL,
      updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY (updated_by_admin_id) REFERENCES admins(id) ON DELETE RESTRICT
    );

CREATE TABLE reports (
      id TEXT PRIMARY KEY,
      reporter_id TEXT NOT NULL,
      target_type TEXT NOT NULL CHECK(target_type IN ('user', 'product', 'wanted', 'chat')),
      target_id TEXT NOT NULL,
      target_user_id TEXT,
      reason TEXT NOT NULL,
      details TEXT DEFAULT '',
      status TEXT NOT NULL DEFAULT 'received'
        CHECK(status IN ('received', 'reviewing', 'resolved', 'dismissed')),
      admin_note TEXT DEFAULT '',
      created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
      resolved_at TIMESTAMPTZ,
      resolved_by_admin_id BIGINT,
      FOREIGN KEY (resolved_by_admin_id) REFERENCES admins(id) ON DELETE SET NULL
    );

CREATE TABLE saved_cards (
        id BIGSERIAL PRIMARY KEY,
        seller_id TEXT NOT NULL REFERENCES sellers(id) ON DELETE CASCADE,
        vendor_id TEXT NOT NULL REFERENCES sellers(id) ON DELETE CASCADE,
        mp_card_id TEXT NOT NULL,
        last_four_digits TEXT,
        payment_method TEXT,
        expiration_month INTEGER,
        expiration_year INTEGER,
        created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        UNIQUE(seller_id, vendor_id, mp_card_id)
      );

CREATE TABLE vendor_payment_accounts (
        id BIGSERIAL PRIMARY KEY,
        seller_id TEXT NOT NULL REFERENCES sellers(id) ON DELETE CASCADE,
        provider TEXT NOT NULL DEFAULT 'mercadopago',
        mp_user_id TEXT NOT NULL,
        mp_access_token_enc TEXT NOT NULL,
        mp_refresh_token_enc TEXT,
        mp_token_expires_at TIMESTAMPTZ,
        mp_public_key TEXT,
        connected_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        revoked_at TIMESTAMPTZ,
        disconnect_reason TEXT,
        disconnected_by TEXT
          CHECK(disconnected_by IS NULL OR disconnected_by IN ('user','webhook','token_check')),
        UNIQUE(seller_id, provider)
      );

CREATE TABLE verificaciones (
      id BIGSERIAL PRIMARY KEY,
      usuario_id TEXT NOT NULL UNIQUE REFERENCES sellers(id) ON DELETE CASCADE,
      tipo_cuenta TEXT NOT NULL CHECK(tipo_cuenta IN ('estudiante','negocio','particular')),
      estado TEXT NOT NULL DEFAULT 'pendiente' CHECK(estado IN ('pendiente','verificado','rechazado')),
      fecha_verificacion TIMESTAMPTZ,
      creado_en TIMESTAMPTZ NOT NULL,

      correo_institucional TEXT,
      matricula TEXT,
      codigo_otp_email TEXT,
      codigo_otp_email_expira TIMESTAMPTZ,

      nombre_negocio TEXT,
      ubicacion_lat DOUBLE PRECISION,
      ubicacion_lng DOUBLE PRECISION,
      link_red_social TEXT,

      telefono TEXT,
      codigo_otp_sms TEXT,
      codigo_otp_sms_expira TIMESTAMPTZ,

      motivo_rechazo TEXT,
      campo_rechazado TEXT,
      intentos_envio INTEGER NOT NULL DEFAULT 0,
      ventana_envio_inicio TIMESTAMPTZ,
      intentos_confirmacion INTEGER NOT NULL DEFAULT 0
    , carrera TEXT, tipo_verificacion TEXT, identidad_confirmada_en TIMESTAMPTZ, responsable_negocio TEXT, solicitud_json TEXT);

CREATE TABLE verification_documents (
      id BIGSERIAL PRIMARY KEY,
      usuario_id TEXT NOT NULL REFERENCES sellers(id) ON DELETE CASCADE,
      doc_type TEXT NOT NULL CHECK(doc_type IN ('responsible_ine_front','responsible_ine_back','additional_evidence')),
      file_url TEXT NOT NULL,
      original_name TEXT NOT NULL,
      mime_type TEXT NOT NULL,
      uploaded_at TIMESTAMPTZ NOT NULL,
      content_hash TEXT
    );

CREATE TABLE wanted_posts (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      title TEXT NOT NULL,
      description TEXT,
      category_id TEXT NOT NULL,
      type TEXT NOT NULL,
      price_min DOUBLE PRECISION,
      price_max DOUBLE PRECISION,
      status TEXT NOT NULL DEFAULT 'abierta',
      resolved_with_user_id TEXT,
      created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
      resolved_at TIMESTAMPTZ
    , updated_at TIMESTAMPTZ, location_lat DOUBLE PRECISION, location_lng DOUBLE PRECISION, paymentMethods TEXT DEFAULT NULL, views INTEGER DEFAULT 0, expires_at TIMESTAMPTZ DEFAULT NULL, moderation_status TEXT NOT NULL DEFAULT 'visible'
      CHECK(moderation_status IN ('visible', 'removed', 'spam')), moderation_reason TEXT, moderated_at TIMESTAMPTZ, moderated_by_admin_id BIGINT REFERENCES admins(id));

CREATE TABLE interacciones_dispositivo (
        id BIGSERIAL PRIMARY KEY,
        device_id TEXT NOT NULL,
        user_id TEXT,
        product_id TEXT,
        category TEXT NOT NULL,
        tipo TEXT NOT NULL CHECK(tipo IN ('vista', 'favorito', 'contacto', 'categoria')),
        created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE
      );

CREATE TABLE order_items (
      id BIGSERIAL PRIMARY KEY,
      order_id TEXT NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
      product_id TEXT NOT NULL,
      quantity INTEGER NOT NULL DEFAULT 1,
      unit_price DOUBLE PRECISION NOT NULL,
      title_snapshot TEXT
    );

CREATE TABLE product_comments (
      id         TEXT PRIMARY KEY,
      product_id TEXT NOT NULL,
      user_id    TEXT NOT NULL,
      texto      TEXT NOT NULL CHECK(length(texto) >= 1 AND length(texto) <= 500),
      created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
      deleted_at TIMESTAMPTZ DEFAULT NULL,
      deleted_by TEXT DEFAULT NULL,
      FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE
    );

CREATE TABLE product_questions (
      id            TEXT PRIMARY KEY,
      product_id    TEXT NOT NULL,
      seller_id     TEXT NOT NULL,
      asked_by      TEXT NOT NULL,
      question_text TEXT NOT NULL CHECK(length(question_text) >= 1 AND length(question_text) <= 500),
      answer_text   TEXT DEFAULT NULL CHECK(answer_text IS NULL OR (length(answer_text) >= 1 AND length(answer_text) <= 500)),
      status        TEXT NOT NULL DEFAULT 'pending' CHECK(status IN ('pending', 'answered')),
      created_at    TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
      answered_at   TIMESTAMPTZ DEFAULT NULL,
      FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE
    );

CREATE TABLE product_ratings (
      product_id TEXT NOT NULL,
      user_id TEXT NOT NULL,
      stars INTEGER NOT NULL CHECK(stars >= 1 AND stars <= 5),
      created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (product_id, user_id),
      FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE
    );

CREATE INDEX idx_admin_audit_log_admin_date
      ON admin_audit_log(admin_id, created_at DESC, id DESC);

CREATE INDEX idx_admin_audit_log_date
      ON admin_audit_log(created_at DESC, id DESC);

CREATE INDEX idx_admin_audit_log_entity_date
      ON admin_audit_log(entity_type, entity_id, created_at DESC, id DESC);

CREATE INDEX idx_admin_revoked_tokens_expiry
      ON admin_revoked_tokens(expires_at);

CREATE INDEX idx_admins_active ON admins(active, id);

CREATE UNIQUE INDEX idx_cart_user_product
      ON cart(user_id, productId) WHERE user_id IS NOT NULL;

CREATE INDEX idx_category_engagement_category_created
      ON category_engagement_events(category_id, created_at);

CREATE INDEX idx_chat_user_settings_target
      ON chat_user_settings(target_id, owner_id);

CREATE INDEX idx_conversation_deletions_user
      ON conversation_deletions(user_id, conversation_id);

CREATE INDEX idx_conversations_buyer ON conversations(buyer_id, last_message_at);

CREATE INDEX idx_conversations_seller ON conversations(seller_id, last_message_at);

CREATE INDEX idx_interacciones_device ON interacciones_dispositivo(device_id, created_at);

CREATE INDEX idx_interacciones_device_categoria ON interacciones_dispositivo(device_id, category, created_at);

CREATE INDEX idx_interacciones_producto_tipo ON interacciones_dispositivo(product_id, tipo);

CREATE INDEX idx_interacciones_user ON interacciones_dispositivo(user_id, created_at);

CREATE INDEX idx_interacciones_user_categoria ON interacciones_dispositivo(user_id, category, created_at);

CREATE INDEX idx_interest_queue_pendientes
      ON interest_notification_queue(processed_at, created_at);

CREATE INDEX idx_messages_conversation ON messages(conversation_id, created_at);

CREATE INDEX idx_notification_log_subject_categoria
      ON notification_log(subject_id, category_id, sent_at);

CREATE INDEX idx_notification_log_subject_tipo
      ON notification_log(subject_id, type, sent_at);

CREATE INDEX idx_notifications_user ON notifications(user_id, created_at);

CREATE INDEX idx_order_items_order ON order_items(order_id);

CREATE INDEX idx_orders_buyer ON orders(buyer_id, created_at DESC);

CREATE INDEX idx_orders_vendor ON orders(vendor_id, created_at DESC);

CREATE INDEX idx_price_history_product ON price_history(product_id, changed_at);

CREATE INDEX idx_product_comments_product
      ON product_comments(product_id, deleted_at, created_at DESC, id DESC);

CREATE INDEX idx_product_comments_user
      ON product_comments(user_id, created_at DESC);

CREATE INDEX idx_product_questions_asked_by
      ON product_questions(asked_by, product_id, created_at DESC);

CREATE INDEX idx_product_questions_product
      ON product_questions(product_id, created_at DESC, id DESC);

CREATE INDEX idx_product_questions_seller
      ON product_questions(seller_id, status, created_at DESC);

CREATE INDEX idx_product_ratings_product ON product_ratings(product_id);

CREATE INDEX idx_products_category ON products(category);

CREATE INDEX idx_products_moderation_created
      ON products(moderation_status, created_at DESC, id DESC);

CREATE INDEX idx_products_seller ON products(seller);

CREATE INDEX idx_products_seller_expiry
      ON products(seller, expires_at, created_at);

CREATE INDEX idx_profile_view_events_profile_time
      ON profile_view_events(profile_id, viewed_at);

CREATE INDEX idx_push_tokens_user ON push_tokens(user_id);

CREATE INDEX idx_refresh_sessions_user
      ON refresh_sessions(user_id, revoked_at);

CREATE INDEX idx_reports_reporter
      ON reports(reporter_id, created_at DESC, id DESC);

CREATE INDEX idx_reports_status_created
      ON reports(status, created_at DESC, id DESC);

CREATE INDEX idx_reports_target
      ON reports(target_type, target_id, created_at DESC, id DESC);

CREATE INDEX idx_revoked_sessions_expiry ON revoked_sessions(expires_at);

CREATE INDEX idx_saved_cards_seller
        ON saved_cards(seller_id, vendor_id);

CREATE INDEX idx_search_queries_created ON search_queries(created_at);

CREATE INDEX idx_search_queries_key
      ON search_queries(query_key, created_at);

CREATE INDEX idx_search_queries_text ON search_queries(query_text, created_at);

CREATE INDEX idx_sellers_admin_status
      ON sellers(admin_status, admin_status_until, id)
  ;

CREATE UNIQUE INDEX idx_sellers_email_unique
      ON sellers(lower(email))
      WHERE email IS NOT NULL AND email <> '';

CREATE UNIQUE INDEX idx_sellers_google_sub
      ON sellers(google_sub) WHERE google_sub IS NOT NULL;

CREATE INDEX idx_sellers_verification_admin
      ON sellers(tipo_cuenta, verified, created_at DESC, id);

CREATE INDEX idx_user_category_interest_categoria
      ON user_category_interest(category_id, interest_score);

CREATE INDEX idx_verificaciones_correo
      ON verificaciones(correo_institucional);

CREATE INDEX idx_verificaciones_telefono
      ON verificaciones(telefono);

CREATE INDEX idx_verification_admin_log_date
      ON verification_admin_log(decided_at DESC, id DESC);

CREATE INDEX idx_verification_admin_log_user_date
      ON verification_admin_log(usuario_id, decided_at DESC, id DESC);

CREATE INDEX idx_verification_documents_file_url ON verification_documents(file_url);

CREATE INDEX idx_verification_documents_hash ON verification_documents(usuario_id, doc_type, content_hash);

CREATE INDEX idx_verification_documents_user ON verification_documents(usuario_id, doc_type, uploaded_at);

CREATE INDEX idx_verification_review_log_date
      ON verification_review_log(decidido_en DESC, id DESC);

CREATE INDEX idx_verification_review_log_user
      ON verification_review_log(usuario_id, id DESC);

CREATE INDEX idx_wanted_moderation_created
      ON wanted_posts(moderation_status, created_at DESC, id DESC);

CREATE INDEX idx_wanted_posts_category ON wanted_posts(category_id, status);

CREATE INDEX idx_wanted_posts_user ON wanted_posts(user_id, created_at);

CREATE INDEX idx_wanted_user_expiry
      ON wanted_posts(user_id, status, expires_at, created_at);

CREATE INDEX IF NOT EXISTS idx_messages_conversation_seq ON messages(conversation_id, seq);
CREATE INDEX IF NOT EXISTS idx_products_expires_at ON products(expires_at) WHERE expires_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_wanted_posts_expires_at ON wanted_posts(expires_at) WHERE expires_at IS NOT NULL;
