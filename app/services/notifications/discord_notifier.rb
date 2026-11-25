require "net/http"
require "json"

module Notifications
  # Posts to a Discord incoming webhook (DISCORD_WEBHOOK, #opsimath).
  # Was the bot REST API until 2026-11-25, reusing the aswarm pipelines'
  # bot token; switched because this only ever posts, and a webhook URL
  # can do nothing but post to its one channel, whereas a bot token can act
  # anywhere the bot can. Hand-rolled `Net::HTTP`, matching
  # `Isfdb::Client`/`Goodreads::RssClient`'s existing style — one POST
  # doesn't warrant a Discord gem dependency.
  class DiscordNotifier
    class ServiceError < StandardError; end

    COLOR_BY_LEVEL = { info: 0x5865F2, warn: 0xFAA61A, error: 0xED4245 }.freeze

    def self.configured?
      ENV["DISCORD_WEBHOOK"].present?
    end

    def initialize(webhook_url: ENV["DISCORD_WEBHOOK"])
      @webhook_url = webhook_url
    end

    def notify(event)
      return if @webhook_url.blank?

      messages = event.embeds.present? ? self.class.pack(event.embeds) : [ [ embed_for(event) ] ]
      messages.each { |embeds| post(embeds) }
    end

    # Discord: at most 10 embeds and 6000 characters to a message.
    MAX_EMBEDS = 10
    MAX_MESSAGE_CHARS = 5800

    # Embeds into as few messages as Discord's limits allow, in order.
    def self.pack(embeds)
      size = ->(list) { list.sum { |e| e[:title].to_s.size + e[:description].to_s.size } }
      embeds.each_with_object([ [] ]) do |embed, messages|
        messages << [] if messages.last.size >= MAX_EMBEDS || (messages.last.any? && size.(messages.last + [ embed ]) > MAX_MESSAGE_CHARS)
        messages.last << embed.compact
      end
    end

    private

    # The error never includes the URL: the webhook URL is the credential,
    # and Notifications.notify logs the message.
    def post(embeds)
      uri = URI(@webhook_url)
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request.body = { embeds: }.to_json

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 5, read_timeout: 10) do |http|
        http.request(request)
      end
      raise ServiceError, "discord returned #{response.code}: #{response.body}" unless response.is_a?(Net::HTTPSuccess)
    end

    # Discord caps an embed description at 4096 characters.
    DESCRIPTION_LIMIT = 4096

    def embed_for(event)
      {
        title: event.title,
        url: event.url.presence,
        description: event.description.presence&.truncate(DESCRIPTION_LIMIT),
        color: COLOR_BY_LEVEL.fetch(event.level, COLOR_BY_LEVEL[:info]),
        fields: Array(event.fields).map { |name, value| { name: name.to_s, value: value.to_s.presence || "—", inline: true } }
      }.compact
    end
  end
end
