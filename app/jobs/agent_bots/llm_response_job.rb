class AgentBots::LlmResponseJob < ApplicationJob
  queue_as :default

  def perform(conversation, agent_bot)
    AgentBots::LlmProcessorService.new(conversation: conversation, agent_bot: agent_bot).perform
  end
end
