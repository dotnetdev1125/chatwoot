class AgentBots::LlmProcessorService
  DEFAULT_SYSTEM_PROMPT = 'You are a helpful customer support assistant. Respond to the customer\'s queries concisely and helpfully.'

  def initialize(conversation:, agent_bot:)
    @conversation = conversation
    @agent_bot = agent_bot
  end

  def perform
    return unless @conversation.pending?
    return unless api_key.present?

    response = generate_response
    return if response.blank?

    send_response(response)
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: @conversation.account).capture_exception
    Rails.logger.error "[AgentBots::LlmProcessorService] Error: #{e.message}"
  end

  private

  def api_key
    @api_key ||= InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_API_KEY')&.value
  end

  def api_base
    endpoint = InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_ENDPOINT')&.value.presence || 'https://api.openai.com'
    "#{endpoint.chomp('/')}/v1"
  end

  def model
    @agent_bot.bot_config['model'].presence || Llm::Config::DEFAULT_MODEL
  end

  def system_prompt
    @agent_bot.bot_config['system_prompt'].presence || DEFAULT_SYSTEM_PROMPT
  end

  def conversation_messages
    # Limit history to prevent excessive memory use for long conversations
    @conversation_messages ||= @conversation.messages
                                             .where(message_type: %i[incoming outgoing], private: false)
                                             .where.not(content: [nil, ''])
                                             .order(:created_at)
                                             .last(50)
                                             .map { |m| { role: m.incoming? ? 'user' : 'assistant', content: m.content } }
  end

  def portal
    @portal ||= @conversation.inbox.portal
  end

  def knowledge_base_tools
    return [] if portal.nil?

    [AgentBots::Tools::SearchKnowledgeBaseTool.new(portal)]
  end

  def generate_response
    Llm::Config.with_api_key(api_key, api_base: api_base) do |context|
      chat = context.chat(model: model)
      chat.with_instructions(system_prompt)

      knowledge_base_tools.each { |tool| chat = chat.with_tool(tool) }

      messages = conversation_messages
      return nil if messages.empty?

      # RubyLLM requires history to be added via add_message; only the final
      # user turn is sent through ask() to trigger the completion request.
      messages[0...-1].each { |msg| chat.add_message(role: msg[:role].to_sym, content: msg[:content]) }

      chat.ask(messages.last[:content]).content
    end
  rescue StandardError => e
    Rails.logger.error "[AgentBots::LlmProcessorService] LLM error: #{e.message}"
    nil
  end

  def send_response(response)
    @conversation.messages.create!(
      content: response,
      message_type: :outgoing,
      account: @conversation.account,
      inbox: @conversation.inbox,
      sender: @agent_bot
    )
  end
end
