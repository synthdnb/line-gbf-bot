#!/usr/bin/env ruby
require 'rubygems'
require 'bundler/setup'

require 'sinatra'
require 'line/bot'
require 'pry'
require 'redis'

set :bind, "0.0.0.0"

def redis
  @redis ||= Redis.new(host: "redis")
end

def client
  @client ||= Line::Bot::Client.new { |config|
    config.channel_secret = ENV["LINE_CHANNEL_SECRET"]
    config.channel_token = ENV["LINE_CHANNEL_TOKEN"]
  }
end

def get_display_name user_id
  response = client.get_profile(user_id)
  case response
  when Net::HTTPSuccess then
    contact = JSON.parse(response.body)
    contact['displayName']
  else
    nil
  end
end

post '/callback' do
  body = request.body.read

  signature = request.env['HTTP_X_LINE_SIGNATURE']
  unless client.validate_signature(body, signature)
    error 400 do 'Bad Request' end
  end

  events = client.parse_events_from(body)
  events.each { |event|
    p event
    case event
    when Line::Bot::Event::Follow
      message = {
        type: 'text',
        text: "기공단 봇입니다. 공지 등을 개인 메시지로 보내줍니다."
      }
      client.reply_message(event['replyToken'], message)
      user_id = event["source"]["userId"]
      redis.sadd "receivers", user_id
      puts "Follow from #{user_id}"
    when Line::Bot::Event::Unfollow
      user_id = event["source"]["userId"]
      redis.srem "receivers", user_id
      puts "UnFollow from #{user_id}"
    when Line::Bot::Event::Message
      case event.type
      when Line::Bot::Event::MessageType::Text
        if event.message['text'].match(/!(\S+)\s+(.+)/)
          cmd = $1
          content = $2
          message = {}
          case cmd
          when "공지"
            break unless event["source"]["type"] == "user"
            sender = get_display_name(event["source"]["userId"])
            message = {
              type: 'text',
              text: "From #{sender}\n#{content}"
            }
            receivers = redis.smembers "receivers" 
            receivers.each do |target|
              client.push_message target, message
            end
            message = {
              type: 'text',
              text: "#{receivers.length}명에게 공지를 발송했습니다"
            }
            client.reply_message(event['replyToken'], message)
          when "일정"
            message = {
              type: 'text',
              text: <<-EOT
              5월 일정
              ~5/9 아스트레이 알케미스트
              5/10~5/15 사상강림
              5/17~5/24 고전장
              5/25~5/30 영웅재기
              5/25~5/30 제노이프리트
              5/31~ 시나리오
              EOT
            }
            client.reply_message(event['replyToken'], message)
          end
        end
      when Line::Bot::Event::MessageType::Image, Line::Bot::Event::MessageType::Video
        # response = client.get_message_content(event.message['id'])
        # tf = Tempfile.open("content")
        # tf.write(response.body)
      end
    end
  }
  "OK"
end
