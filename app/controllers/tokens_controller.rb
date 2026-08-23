class TokensController < ApplicationController
  before_action :set_token

  # The card shell: renders straight from precomputed grammar, so it appears
  # without waiting on anything. Its nested frame then fetches the translation.
  def show
    @entry = current_user.vocab_entries.find_by(lemma_id: @token.lemma_id)
    @bookmark = current_user.bookmarks.find_by(block_id: @token.block_id,
                                               word_position: @token.position)
    @bookmark_count = current_user.bookmarks.where(book_id: @token.book_id).count
  end

  # Loaded by the frame inside the card. This is the only request that can hit a
  # language model, and only on a cache miss.
  def gloss
    @gloss = Translator.lookup(@token)
    @unavailable = @gloss.nil?
  rescue Translator::Error => error
    Rails.logger.warn("[translator] #{error.message}")
    @gloss = nil
    @failed = true
  end

  private

  def set_token
    @token = find_token(params[:id])
  end
end
