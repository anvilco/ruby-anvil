# frozen_string_literal: true

module Anvil
  module Payloads
    # The variables of a {Anvil::Client#forge_submit} call: a submission to one
    # webform (a Forge) of a Workflow. Every argument is generated from the
    # schema into {Anvil::Operations::ForgeSubmitArgs}.
    #
    # Leave `weld_data_eid` out to start a new submission; pass the one you got
    # back to add to an existing submission.
    #
    # @see https://www.useanvil.com/docs/api/workflows
    class ForgeSubmit < Anvil::Operations::ForgeSubmitArgs
    end
  end
end
