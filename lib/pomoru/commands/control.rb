# frozen_string_literal: true

require 'discordrb'
require 'dotenv/load'
require_relative '../config/config'
require_relative '../config/user_messages'
require_relative '../session/countdown'
require_relative '../session/session'
require_relative '../session/session_controller'
require_relative '../session/session_manager'
require_relative '../message_builder'
require_relative '../settings'
require_relative '../state_handler'
require_relative '../state'

module Bot::Commands
  module Control
    extend Discordrb::Commands::CommandContainer

    command :start do |event, pomodoro = 25, short_break = 5, long_break = 15, intervals = 4|
      if event.user.voice_channel.nil?
        event.send_message("ボイスチャンネルに参加して#{ENV['PREFIX']}#{event.command.name}を実行してください")
        return
      end
      session = SessionManager::ACTIVE_SESSIONS[SessionManager.session_id_from(event)]
      if session
        event.send_message(ACTIVE_SESSION_EXISTS_ERR)
        return
      end
      if Settings.invalid?(pomodoro, short_break, long_break, intervals)
        event.send_message("1〜#{MAX_INTERVAL_MINUTES}分までのパラメータを入力してください")
        return
      end

      session = Session.new(
        state: State::POMODORO,
        set: Settings.new(
          pomodoro,
          short_break,
          long_break,
          intervals
        ),
        ctx: event
      )
      session.timer.running = true
      SessionController.start(session)
    end

    command :pause do |event|
      session = SessionManager.get_session(event)
      return if Countdown.running?(session)
      if session
        timer = session.timer
        unless timer.running
          event.send_message('タイマーは既に一時停止しています')
          return
        end
        timer.running = false
        timer.remaining = timer.end.to_i - Time.now.to_i
        session.message.edit('', MessageBuilder.status_embed(session))
        event.send_message("#{session.state}を一時停止しました")
      end
    end

    command :resume do |event|
      session = SessionManager.get_session(event)
      return if Countdown.running?(session)
      if session
        timer = session.timer
        if session.timer.running
          event.send_message('タイマーは既に実行されています')
          return
        end
        timer.running = true
        timer.end = Time.now + timer.remaining
        session.message.edit('', MessageBuilder.status_embed(session))
        event.send_message("#{session.state}を再開しました")
        SessionController.resume(session)
      end
    end

    command :restart do |event|
      session = SessionManager.get_session(event)
      return if Countdown.running?(session)
      if session
        session.timer.time_remaining_update(session)
        event.send_message("#{session.state}をリスタートしました")
        SessionController.resume(session)
      end
    end

    command :skip do |event|
      session = SessionManager.get_session(event)
      return if Countdown.running?(session)
      if session
        stats = session.stats
        if stats.pomos_completed >= 0 && session.state == State::POMODORO
          stats.pomos_completed -= 1
          stats.minutes_completed -= session.settings.pomodoro
        end
        event.send_message("#{session.state}をスキップしました")
        StateHandler.transition(session)
        session.message.edit('', MessageBuilder.status_embed(session))
        SessionController.resume(session)
      end
    end

    command :end do |event|
      session = SessionManager.get_session(event)
      if session
        if session.stats.pomos_completed.positive?
          completed_message = event.send_message("おつかれさまです！#{MessageBuilder.stats_msg(session.stats)}")
          completed_message.create_reaction('👍')
        else
          incomplete_message = event.send_message('また会いましょう！')
          incomplete_message.create_reaction('👋')
        end
        SessionController.end(session)
      end
    end

    command :edit do |event, pomodoro = nil, short_break = nil, long_break = nil, intervals = nil|
      session = SessionManager.get_session(event)
      return if Countdown.running?(session)
      if session
        if pomodoro.nil?
          event.send_message(MISSING_ARG_ERR)
          return
        end
        if Settings.invalid?(pomodoro, short_break, long_break, intervals)
          event.send_message("1〜#{MAX_INTERVAL_MINUTES}分までのパラメータを入力してください")
          return
        end
        SessionController.edit(session, Settings.new(
                                          pomodoro,
                                          short_break,
                                          long_break,
                                          intervals
                                        ))
        SessionMessenger.send_edit_msg(session)
        SessionMessenger.send_remind_msg(session) if session.reminder.running
        SessionController.resume(session)
      end
    end
  end
end
