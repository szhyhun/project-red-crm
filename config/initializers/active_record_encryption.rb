# Integration credentials live in the database, never in organization settings or
# source code. Production may supply dedicated rotation keys; development falls
# back to stable keys derived from Rails' secret_key_base.
encryption = Rails.application.config.active_record.encryption
key_generator = Rails.application.key_generator
encryption.primary_key ||= ENV.fetch("ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY") do
  key_generator.generate_key("project-red-active-record-encryption-primary", 32)
end
encryption.deterministic_key ||= ENV.fetch("ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY") do
  key_generator.generate_key("project-red-active-record-encryption-deterministic", 32)
end
encryption.key_derivation_salt ||= ENV.fetch("ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT") do
  key_generator.generate_key("project-red-active-record-encryption-salt", 32)
end
