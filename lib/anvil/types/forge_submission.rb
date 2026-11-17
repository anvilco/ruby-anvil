# frozen_string_literal: true

module Anvil
  module Types
    # A submission to a Workflow's webform.
    class ForgeSubmission < Base
      attribute :id
      attribute :eid
      attribute :status
      attribute :continue_url, key: "continueURL"
      attribute :payload_value
      attribute :current_step
      attribute :completed_at, type: :time
      attribute :created_at, type: :time
      attribute :updated_at, type: :time
      attribute :signer, type: Signer
      attribute :weld_data, type: WeldData
    end
  end
end
