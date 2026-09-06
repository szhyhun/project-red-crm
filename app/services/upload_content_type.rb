module UploadContentType
  module_function

  def for(uploaded_file)
    tempfile = uploaded_file.tempfile
    tempfile.rewind
    detected_type = Marcel::MimeType.for(tempfile, name: uploaded_file.original_filename).presence
    declared_type = uploaded_file.content_type.presence

    detected_type.presence || declared_type || "application/octet-stream"
  ensure
    tempfile&.rewind
  end
end
