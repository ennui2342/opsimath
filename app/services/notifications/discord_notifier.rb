require "net/http"
require "json"

module Notifications
  # Posts to a Discord channel via the bot REST API
  # (`POST /channels/{id}/messages`, `Authorization: Bot {token}`) — the
  # same mechanism the existing aswarm Goodreads pipelines already use
  # (`~/projects/aswarm/src/aswarm/connectors/discord.py`'s `_send_channel`,
  # itself a thin wrapper over this exact endpoint), reusing their real
  # bot token/channel id rather than setting up a separate incoming
  # webhook. Hand-rolled `Net::HTTP`, matching `Isfdb::Client`/
  # `Goodreads::RssClient`'s existing style — one POST doesn't warrant a
  # Discord gem dependency.
  class DiscordNotifier
    class ServiceError < StandardError; end

    COLOR_BY_LEVEL = { info: 0x5865F2, warn: 0xFAA61A, error: 0xED4245 }.freeze

    def initialize(bot_token: Rails.application.credentials.dig(:discord, :bot_token),
                    channel_id: Rails.application.credentials.dig(:discord, :channel_id))
      @bot_token = bot_token
      @channel_id = channel_id
    end

    def notify(event)
      uri = URI("https://discord.com/api/v10/channels/#{@channel_id}/messages")
      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bot #{@bot_token}"
      request["Content-Type"] = "application/json"
      request.body = { embeds: [ embed_for(event) ] }.to_json

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) do |http|
        http.request(request)
      end
      raise ServiceError, "discord returned #{response.code}: #{response.body}" unless response.is_a?(Net::HTTPSuccess)
    end

    private

    def embed_for(event)
      {
        title: event.title,
        color: COLOR_BY_LEVEL.fetch(event.level, COLOR_BY_LEVEL[:info]),
        fields: event.fields.map { |name, value| { name: name.to_s, value: value.to_s.presence || "—", inline: true } }
      }
    end
  end
end
