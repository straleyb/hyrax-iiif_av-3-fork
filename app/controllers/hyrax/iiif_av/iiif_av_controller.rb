# frozen_string_literal: true
module Hyrax
  module IiifAv
    class IiifAvController < ApplicationController
      include Blacklight::Base
      include Blacklight::AccessControls::Catalog

      def content
        file_set_id = params[:id]
        label = params[:label]
        if request.head?
          return head :ok if valid_token?
          return head :unauthorized
        else
          return head :unauthorized unless presenter
          return redirect_to hyrax.download_path(file_set_id, file: label, locale: nil) unless stream_urls[label]
          redirect_to stream_urls[label]
        end
      end

      def auth_token
        return head :unauthorized unless can? :read, params[:id]
        render html: auth_token_html_response(generate_auth_token)
      end

      private

        def generate_auth_token
          session["iiif_auth_tokens"] ||= {}
          # This is the same method used by ActiveRecord::SecureToken
          session["iiif_auth_tokens"][params[:id]] = SecureRandom.base58(24)
        end

        # rubocop:disable Rails/OutputSafety
        def auth_token_html_response(token)
          message = { messageId: params[:messageId], accessToken: token }
          origin = Rails::Html::FullSanitizer.new.sanitize(params[:origin])
          "<html><body><script>window.parent.postMessage(#{message.to_json}, \"#{origin}\");</script></body></html>".html_safe
        end # rubocop:enable Rails/OutputSafety

        def valid_token?
          auth_token = request.headers['Authorization']&.sub('Bearer ', '')
          session["iiif_auth_tokens"] && session["iiif_auth_tokens"][params[:id]] == auth_token
        end

        def presenter
          @presenter ||= begin
            _, document_list = search_results(params)
            curation_concern = document_list.first
            return nil unless curation_concern
            # Use the show presenter configured in the FileSetsController
            Hyrax::FileSetsController.show_presenter.new(curation_concern, current_ability, request)
          end
        end

        # Duplicated here from Hyrax::IiifAv::DisplaysContent
        def stream_urls
          @stream_urls ||= begin
            return {} unless presenter.solr_document['derivatives_metadata_ssi'].present?
            files_metadata = JSON.parse(presenter.solr_document['derivatives_metadata_ssi'])
            file_locations = files_metadata.select { |f| f['file_location_uri'].present? }
            return {} unless file_locations.present?
            streams = {}
            file_locations.each do |f|
              streams[f['label']] = Hyrax::IiifAv.config.iiif_av_url_builder.call(
                f['file_location_uri'],
                request.base_url
              )
            end
            streams
          end
        end
    end
  end
end
