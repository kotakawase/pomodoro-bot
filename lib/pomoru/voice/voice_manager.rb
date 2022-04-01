# frozen_string_literal: true

require 'dotenv/load'
require_relative '../config/user_messages'
require_relative './voice_accessor'

class VoiceManager
  # rubocop:disable Style/MutableConstant
  CONNECTED_SESSIONS = {}
  # rubocop:enable Style/MutableConstant

  CLIENT_ID = ENV['CLIENT_ID']

  class << self
    def connect(session)
      event = session.event
      if event.voice && get_connected_session(event)
        event.send_message(ACTIVE_SESSION_EXISTS_ERR)
        return
      end
      voice_client = event.bot.voice_connect(event.user.voice_channel)
      event.bot.member(event.server.id, CLIENT_ID).server_deafen
      event.bot.game = VoiceAccessor.get_voice_channel(session).name.to_s
      CONNECTED_SESSIONS[voice_channel_id_from(event)] = session if voice_client
      true
    end

    def disconnect(session)
      CONNECTED_SESSIONS.delete(voice_channel_id_from(session.event))
      session.event.bot.update_status('online', nil, nil)
      session.event.bot.voice_destroy(session.event.server.id)
    end

    private

    def get_connected_session(event)
      session = CONNECTED_SESSIONS[voice_channel_id_from(event)]
      return unless session
    end

    def voice_channel_id_from(event)
      event.server.id.to_s + event.channel.id.to_s
    end
  end
end
