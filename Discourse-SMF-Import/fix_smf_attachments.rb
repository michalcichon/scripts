# /var/www/discourse/script/fix_smf_attachments.rb
# Usage:
# RAILS_ENV=production \
#   SMF_HOST=localhost SMF_DB=smfdb SMF_USER=smfuser SMF_PASS=smfpass SMF_PREFIX=smf_ \
#   bundle exec rails runner script/fix_smf_attachments.rb

require 'mysql2'

SMF_HOST   = ENV['SMF_HOST']   || 'localhost'
SMF_DB     = ENV['SMF_DB']     || raise('Set SMF_DB')
SMF_USER   = ENV['SMF_USER']   || Etc.getlogin
SMF_PASS   = ENV['SMF_PASS']   || ''
SMF_PREFIX = ENV['SMF_PREFIX'] || 'smf_'

client = Mysql2::Client.new(host: SMF_HOST, username: SMF_USER, password: SMF_PASS, database: SMF_DB, symbolize_keys: true)

def post_has_upload_markdown?(raw)
  raw&.include?('/uploads/') || raw&.match?(/\(upload:\/\/[a-z0-9]+\)/)
end

def append_upload_markdown!(post, upload, sep_needed)
  # Discourse akceptuje taki markdown dla plików/obrazów:
  # ![nazwa|attachment](upload://hash.ext)
  post.raw ||= ''
  post.raw << "\n\n---" if sep_needed && !post.raw.strip.end_with?('---')
  post.raw << "\n\n![#{upload.original_filename}|attachment](#{upload.short_url})"
end

# Zbierz wszystkie import_id -> post_id
pairs = PostCustomField
  .where(name: 'import_id')
  .pluck(:post_id, :value) # [post_id, '12345' albo 'pm-123']
  .select { |_, v| v !~ /\Apm-/ } # tylko zwykłe posty (nie PM)

puts "Found #{pairs.size} imported posts"

updated = 0
skipped = 0
missing_uploads = 0

pairs.each_slice(1000) do |slice|
  posts = Post.where(id: slice.map(&:first)).includes(:topic, :user).to_a
  slice.each do |post_id, import_id|
    post = posts.find { |p| p.id == post_id }
    next unless post

    # jeśli już ma uploady w treści — pomiń
    if post_has_upload_markdown?(post.raw)
      skipped += 1
      next
    end

    # pobierz listę załączników z SMF dla tego id_msg
    rows = client.query(<<~SQL, symbolize_keys: true).to_a
      SELECT id_attach, file_hash, filename
      FROM #{client.escape(SMF_PREFIX)}attachments
      WHERE attachment_type = 0 AND id_msg = #{import_id.to_i}
      ORDER BY id_attach ASC
    SQL

    if rows.empty?
      skipped += 1
      next
    end

    # spróbuj dopasować Upload w Discourse po nazwie pliku i autorze
    # (importer tworzył Uploady właśnie dla user_id posta)
    sep = true
    rows.each do |r|
      upload = Upload
        .where(user_id: post.user_id, original_filename: r[:filename])
        .order('created_at ASC')
        .last

      if upload
        append_upload_markdown!(post, upload, sep)
        sep = false
      else
        # plan B: spróbuj po samej nazwie (ktoś mógł zmienić usera)
        upload = Upload.where(original_filename: r[:filename]).order('created_at ASC').last
        if upload
          append_upload_markdown!(post, upload, sep)
          sep = false
        else
          missing_uploads += 1
        end
      end
    end

    if post.changed?
      Post.transaction do
        post.save!(validate: false)
        post.rebake!
      end
      updated += 1
    else
      skipped += 1
    end
  end
  puts "Progress: updated=#{updated}, skipped=#{skipped}, missing_uploads=#{missing_uploads}"
end

puts "DONE. updated=#{updated}, skipped=#{skipped}, missing_uploads=#{missing_uploads}"
