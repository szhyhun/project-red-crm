class Api::V1::ClientAccountTagsController < Api::V1::BaseController
  # Replaces a team's tags with the ones chosen.
  def update
    account = policy_scope(ClientAccount).find(params[:client_account_id])
    authorize account, :update?
    tag_ids = Array(params.require(:client_account).fetch(:tag_ids, [])).compact_blank.map(&:to_i).uniq
    tags = policy_scope(Tag).where(id: tag_ids)
    return render json: { error: "unknown_tag", details: { base: [ "Choose tags from this organization" ] } }, status: :unprocessable_content if tags.size != tag_ids.size

    ClientAccountTag.transaction do
      account.client_account_tags.where.not(tag_id: tag_ids).destroy_all
      tags.each { |tag| account.client_account_tags.find_or_create_by!(tag:) }
    end

    render json: { tags: account.tags.order(:name).map { |tag| tag.slice(:id, :name, :color) } }
  end
end
