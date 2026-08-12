class Api::V1::ListingNotesController < Api::V1::BaseController
  def create
    listing = policy_scope(Listing).find(params[:listing_id])
    authorize listing, :update?
    attributes = note_params.to_h.symbolize_keys
    html = attributes.delete(:body_html)
    attributes[:body] = sanitize_note_html(html) if html.present?
    attributes[:body_format] = "html" if html.present?
    note = listing.listing_notes.build(attributes.merge(organization: Current.organization, author: current_user))

    if note.save
      ActivityEvent.create!(organization: Current.organization, actor: current_user, subject: listing,
                            event_type: "listing_note.created", payload: { note_type: note.note_type })
      render json: { listing_note: serialize(note) }, status: :created
    else
      render_validation_errors(note)
    end
  end

  def destroy
    note = ListingNote.joins(:listing).merge(policy_scope(Listing)).find(params[:id])
    authorize note.listing, :update?
    note.destroy!
    head :no_content
  end

  private

  def note_params
    params.require(:listing_note).permit(:note_type, :body, :body_html)
  end

  def serialize(note)
    note.slice(:id, :note_type, :body, :body_format, :created_at).merge(
      body_html: note.body_format == "html" ? note.body : ERB::Util.html_escape(note.body).gsub("\n", "<br>").html_safe,
      author: note.author.slice(:id, :name)
    )
  end

  def sanitize_note_html(value)
    ActionController::Base.helpers.sanitize(
      value.to_s,
      tags: %w[p br strong em ul ol li a],
      attributes: %w[href target rel]
    )
  end
end
