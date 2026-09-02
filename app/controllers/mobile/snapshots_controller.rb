module Mobile
  # Serves the offline shop-lookup snapshot (docs/MOBILE.md). Bearer-token
  # auth, not the human session — this is the PWA fetching in the
  # background. `version` is cheap to poll; `show` supports conditional
  # GET so an unchanged snapshot isn't re-downloaded.
  class SnapshotsController < ActionController::Base
    include TokenAuthentication

    def version
      snapshot = MobileSnapshot.current
      return head :not_found unless snapshot&.file&.attached?

      render json: {
        version: snapshot.version,
        generated_at: snapshot.generated_at&.iso8601,
        bytes: snapshot.byte_size
      }
    end

    def show
      snapshot = MobileSnapshot.current
      return head :not_found unless snapshot&.file&.attached?

      blob = snapshot.file.blob
      return unless stale?(etag: blob.checksum, last_modified: snapshot.generated_at)

      send_data blob.download, filename: "snapshot.sqlite3",
                type: "application/vnd.sqlite3", disposition: "attachment"
    end
  end
end
