# frozen_string_literal: true

module Sass
  class Embedded
    class Host
      # The {ImporterRegistry} class.
      #
      # It stores importers and handles import requests.
      class ImporterRegistry
        attr_reader :importers

        def initialize(importers, load_paths, alert_color:)
          @id = 0
          @importers_by_id = {}
          @importers = importers
                       .map { |importer| register(importer) }
                       .concat(
                         load_paths.map do |load_path|
                           EmbeddedProtocol::InboundMessage::CompileRequest::Importer.new(
                             path: File.absolute_path(load_path)
                           )
                         end
                       )

          @highlight = alert_color
        end

        def register(importer)
          importer = Structifier.to_struct(importer)

          is_importer = importer.respond_to?(:canonicalize) && importer.respond_to?(:load)
          is_file_importer = importer.respond_to?(:find_file_url)

          raise ArgumentError, 'importer must be an Importer or a FileImporter' if is_importer == is_file_importer

          proto = if is_importer
                    EmbeddedProtocol::InboundMessage::CompileRequest::Importer.new(
                      importer_id: @id
                    )
                  else
                    EmbeddedProtocol::InboundMessage::CompileRequest::Importer.new(
                      file_importer_id: @id
                    )
                  end
          @importers_by_id[@id] = importer
          @id = @id.next
          proto
        end

        def canonicalize(canonicalize_request)
          importer = @importers_by_id[canonicalize_request.importer_id]
          url = importer.canonicalize(canonicalize_request.url, from_import: canonicalize_request.from_import)&.to_s

          EmbeddedProtocol::InboundMessage::CanonicalizeResponse.new(
            id: canonicalize_request.id,
            url: url
          )
        rescue StandardError => e
          EmbeddedProtocol::InboundMessage::CanonicalizeResponse.new(
            id: canonicalize_request.id,
            error: e.full_message(highlight: @highlight, order: :top)
          )
        end

        def import(import_request)
          importer = @importers_by_id[import_request.importer_id]
          importer_result = Structifier.to_struct importer.load(import_request.url)

          EmbeddedProtocol::InboundMessage::ImportResponse.new(
            id: import_request.id,
            success: EmbeddedProtocol::InboundMessage::ImportResponse::ImportSuccess.new(
              contents: importer_result.contents,
              syntax: Protofier.to_proto_syntax(importer_result.syntax),
              source_map_url: (importer_result.source_map_url&.to_s if importer_result.respond_to?(:source_map_url))
            )
          )
        rescue StandardError => e
          EmbeddedProtocol::InboundMessage::ImportResponse.new(
            id: import_request.id,
            error: e.full_message(highlight: @highlight, order: :top)
          )
        end

        def file_import(file_import_request)
          importer = @importers_by_id[file_import_request.importer_id]
          file_url = importer.find_file_url(file_import_request.url, from_import: file_import_request.from_import)&.to_s

          if !file_url.nil? && !file_url.start_with?('file:')
            raise "file_url must be a file: URL, was #{file_url.inspect}"
          end

          EmbeddedProtocol::InboundMessage::FileImportResponse.new(
            id: file_import_request.id,
            file_url: file_url
          )
        rescue StandardError => e
          EmbeddedProtocol::InboundMessage::FileImportResponse.new(
            id: file_import_request.id,
            error: e.full_message(highlight: @highlight, order: :top)
          )
        end
      end

      private_constant :ImporterRegistry
    end
  end
end
