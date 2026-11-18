# frozen_string_literal: true

module Anvil
  # The GraphQL operations this client sends.
  #
  # The operation text and the default response queries are kept identical to
  # node-anvil's `src/graphql/` directory, so the same call returns the same
  # fields whichever client you use. Pass your own `response_query` to any of
  # these to select different fields, or your own `mutation` to replace the
  # operation outright.
  module GraphQL
    # The fields each operation selects when you do not ask for others.
    module DefaultResponseQueries
      CREATE_ETCH_PACKET = <<~GRAPHQL.strip
        {
          eid
          name
          status
          isTest
          allowUpdates
          numberRemainingSigners
          detailsURL
          webhookURL
          completedAt
          archivedAt
          createdAt
          updatedAt
          documentGroup {
            eid
            status
            files
            signers {
              eid
              aliasId
              routingOrder
              name
              email
              status
              signActionType
            }
          }
        }
      GRAPHQL

      CURRENT_USER = <<~GRAPHQL.strip
        {
          eid
          name
          email
          role
          organizations {
            eid
            name
            slug
          }
        }
      GRAPHQL

      ETCH_PACKET = <<~GRAPHQL.strip
        {
          id
          eid
          name
          status
          isTest
          numberRemainingSigners
          webhookURL
          detailsURL
          completedAt
          archivedAt
          createdAt
          updatedAt
          documentGroup {
            id
            eid
            status
            files
            signers {
              id
              eid
              aliasId
              routingOrder
              name
              email
              status
              signActionType
            }
          }
        }
      GRAPHQL

      FORGE_SUBMIT = <<~GRAPHQL.strip
        {
          id
          eid
          status
          continueURL
          payloadValue
          currentStep
          completedAt
          createdAt
          updatedAt
          signer {
            name
            email
            status
            routingOrder
          }
          weldData {
            id
            eid
            isTest
            isComplete
            agents
          }
        }
      GRAPHQL
    end

    # The mutations with a method of their own on {Client}.
    module Mutations
      module_function

      # @param response_query [String] the fields to select on the new packet
      # @return [String]
      def create_etch_packet(response_query = DefaultResponseQueries::CREATE_ETCH_PACKET)
        <<~GRAPHQL
          mutation CreateEtchPacket(
            $name: String,
            $organizationEid: String,
            $files: [EtchFile!],
            $isDraft: Boolean,
            $isTest: Boolean,
            $signatureEmailSubject: String,
            $signatureEmailBody: String,
            $signatureProvider: String,
            $signaturePageOptions: JSON,
            $signers: [JSON!],
            $data: JSON,
            $webhookURL: String,
            $replyToName: String,
            $replyToEmail: String,
            $enableEmails: JSON,
            $createCastTemplatesFromUploads: Boolean,
            $duplicateCasts: Boolean,
            $mergePDFs: Boolean,
            $allowUpdates: Boolean
          ) {
            createEtchPacket(
              name: $name,
              organizationEid: $organizationEid,
              files: $files,
              isDraft: $isDraft,
              isTest: $isTest,
              signatureEmailSubject: $signatureEmailSubject,
              signatureEmailBody: $signatureEmailBody,
              signatureProvider: $signatureProvider,
              signaturePageOptions: $signaturePageOptions,
              signers: $signers,
              data: $data,
              webhookURL: $webhookURL,
              replyToName: $replyToName,
              replyToEmail: $replyToEmail,
              enableEmails: $enableEmails,
              createCastTemplatesFromUploads: $createCastTemplatesFromUploads,
              duplicateCasts: $duplicateCasts,
              mergePDFs: $mergePDFs,
              allowUpdates: $allowUpdates
            ) #{response_query}
          }
        GRAPHQL
      end

      # @param response_query [String] the fields to select on the submission
      # @return [String]
      def forge_submit(response_query = DefaultResponseQueries::FORGE_SUBMIT)
        <<~GRAPHQL
          mutation ForgeSubmit(
            $forgeEid: String!,
            $weldDataEid: String,
            $submissionEid: String,
            $payload: JSON!,
            $enforcePayloadValidOnCreate: Boolean,
            $currentStep: Int,
            $complete: Boolean,
            $isTest: Boolean,
            $timezone: String,
            $webhookURL: String,
            $groupArrayId: String,
            $groupArrayIndex: Int
          ) {
            forgeSubmit(
              forgeEid: $forgeEid,
              weldDataEid: $weldDataEid,
              submissionEid: $submissionEid,
              payload: $payload,
              enforcePayloadValidOnCreate: $enforcePayloadValidOnCreate,
              currentStep: $currentStep,
              complete: $complete,
              isTest: $isTest,
              timezone: $timezone,
              webhookURL: $webhookURL,
              groupArrayId: $groupArrayId,
              groupArrayIndex: $groupArrayIndex
            ) #{response_query}
          }
        GRAPHQL
      end

      # The mutation returns the URL itself, so it selects no fields.
      #
      # @return [String]
      def generate_etch_sign_url
        <<~GRAPHQL
          mutation GenerateEtchSignURL (
            $signerEid: String!,
            $clientUserId: String!,
          ) {
            generateEtchSignURL (
              signerEid: $signerEid,
              clientUserId: $clientUserId
            )
          }
        GRAPHQL
      end

      # @return [String]
      def remove_weld_data
        <<~GRAPHQL
          mutation RemoveWeldData (
            $eid: String!,
          ) {
            removeWeldData (
              eid: $eid,
            )
          }
        GRAPHQL
      end
    end

    # The queries with a method of their own on {Client}.
    module Queries
      module_function

      # @param response_query [String] the fields to select on the user
      # @return [String]
      def current_user(response_query = DefaultResponseQueries::CURRENT_USER)
        <<~GRAPHQL
          query CurrentUser {
            currentUser #{response_query}
          }
        GRAPHQL
      end

      # @param response_query [String] the fields to select on the packet
      # @return [String]
      def etch_packet(response_query = DefaultResponseQueries::ETCH_PACKET)
        <<~GRAPHQL
          query EtchPacket (
            $eid: String!,
          ) {
            etchPacket (
              eid: $eid,
            ) #{response_query}
          }
        GRAPHQL
      end
    end
  end
end
