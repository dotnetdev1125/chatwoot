require 'ruby_llm'

class AgentBots::Tools::SearchKnowledgeBaseTool < RubyLLM::Tool
  RESULTS_LIMIT = 3

  description 'Search the knowledge base for articles relevant to the customer\'s question'
  param :query, desc: 'The search query to find relevant knowledge base articles', required: true

  def initialize(portal)
    @portal = portal
    super()
  end

  def execute(query:)
    Rails.logger.info { "#{self.class.name}: searching portal #{@portal.id} for #{query.inspect}" }

    articles = @portal.articles
                      .where(status: :published)
                      .text_search(query)
                      .limit(RESULTS_LIMIT)

    return 'No relevant articles found.' if articles.empty?

    articles.map { |article| format_article(article) }.join("\n---\n")
  rescue StandardError => e
    Rails.logger.error "#{self.class.name}: search failed - #{e.message}"
    'Knowledge base search is currently unavailable.'
  end

  private

  def format_article(article)
    summary_line = article.description.present? ? "Summary: #{article.description}\n" : ''
    <<~TEXT
      Title: #{article.title}
      #{summary_line}Content:
      #{article.content}
    TEXT
  end
end
