# frozen_string_literal: true

module Anvil
  module Payloads
    # The variables of a {Anvil::Client#forge_submit} call: a submission to one
    # webform (a Forge) of a Workflow.
    #
    # Leave `weld_data_eid` out to start a new submission; pass the one you got
    # back to add to an existing submission.
    #
    # @see https://www.useanvil.com/docs/api/workflows
    class ForgeSubmit < Base
      # @return [String] the eid of the webform being submitted to
      attribute :forge_eid
      # @return [String] the eid of the Workflow submission to add to
      attribute :weld_data_eid
      # @return [String] the eid of a specific submission to update
      attribute :submission_eid
      # @return [Hash] the submitted data, keyed by the webform's field ids
      attribute :payload
      attribute :enforce_payload_valid_on_create
      attribute :current_step
      attribute :complete
      attribute :is_test
      attribute :timezone
      attribute :webhook_url, key: "webhookURL"
      attribute :group_array_id
      attribute :group_array_index
    end
  end
end
