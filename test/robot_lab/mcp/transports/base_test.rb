# frozen_string_literal: true

require "test_helper"

class RobotLab::MCP::Transports::BaseTest < Minitest::Test
  def test_initialization_stores_config
    config = { url: "http://example.com", timeout: 30 }
    transport = RobotLab::MCP::Transports::Base.new(config)

    assert_equal "http://example.com", transport.config[:url]
    assert_equal 30, transport.config[:timeout]
  end

  def test_initialization_symbolizes_string_keys
    config = { "url" => "http://example.com", "timeout" => 30 }
    transport = RobotLab::MCP::Transports::Base.new(config)

    assert_equal "http://example.com", transport.config[:url]
    assert_equal 30, transport.config[:timeout]
  end

  def test_connect_raises_not_implemented
    transport = RobotLab::MCP::Transports::Base.new({})

    assert_raises(NotImplementedError) do
      transport.connect
    end
  end

  def test_send_request_raises_not_implemented
    transport = RobotLab::MCP::Transports::Base.new({})

    assert_raises(NotImplementedError) do
      transport.send_request({})
    end
  end

  def test_close_raises_not_implemented
    transport = RobotLab::MCP::Transports::Base.new({})

    assert_raises(NotImplementedError) do
      transport.close
    end
  end

  def test_connected_returns_false_by_default
    transport = RobotLab::MCP::Transports::Base.new({})

    refute transport.connected?
  end
end
