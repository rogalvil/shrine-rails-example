require "shrine"

if Rails.env.production?
  require "shrine/storage/s3"

  s3_options = {
    access_key_id:     Rails.application.secrets.s3_access_key_id,
    secret_access_key: Rails.application.secrets.s3_secret_access_key,
    region:            Rails.application.secrets.s3_region,
    bucket:            Rails.application.secrets.s3_bucket,
  }

  Shrine.storages = {
    cache: Shrine::Storage::S3.new(prefix: "cache", **s3_options),
    store: Shrine::Storage::S3.new(**s3_options),
  }
else
  require "shrine/storage/gridfs"

  client = Mongo::Client.new("mongodb://127.0.0.1:27017/mbs")

  options = {
    client: client,
    chunk_size: 1*1024*1024,
    batch_size: 10*1024*1024,

  }

  Shrine.storages = {
    cache: Shrine::Storage::Gridfs.new(prefix: "temp", **options),
    store: Shrine::Storage::Gridfs.new(prefix: "fs", **options),
  }
end

Shrine.plugin :activerecord
Shrine.plugin :backgrounding
Shrine.plugin :logging
Shrine.plugin :determine_mime_type
Shrine.plugin :cached_attachment_data
Shrine.plugin :restore_cached_data



if Rails.env.production?
  Shrine.plugin :presign_endpoint, presign_options: -> (request) {
    # Uppy will send the "filename" and "type" query parameters
    filename = request.params["filename"]
    type     = request.params["type"]

    {
      content_disposition:    "inline; filename=\"#{filename}\"", # set download filename
      content_type:           type,                               # set content type (defaults to "application/octet-stream")
      content_length_range:   0..(10*1024*1024),                  # limit upload size to 10 MB
    }
  }
else
  Shrine.plugin :upload_endpoint
end
Shrine.plugin :download_endpoint, storages: Shrine.storages, prefix: "attachments"

Shrine::Attacher.promote { |data| PromoteJob.perform_async(data) }
Shrine::Attacher.delete { |data| DeleteJob.perform_async(data) }
