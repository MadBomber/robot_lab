#!/usr/bin/env ruby
# frozen_string_literal: true

# Example 6: Prompt Templates with ruby_llm-template
#
# Demonstrates using ruby_llm-template for organized, reusable prompts
# within a RobotLab network. This example shows an e-commerce support
# system with dynamic context injection.
#
# Usage:
#   ANTHROPIC_API_KEY=your_key ruby examples/06_prompt_templates.rb
#
# Dependencies:
#   gem install ruby_llm-template
#
# Template Structure:
#   examples/prompts/
#   ├── triage/
#   │   ├── system.txt.erb
#   │   └── user.txt.erb
#   ├── order_support/
#   │   ├── system.txt.erb
#   │   └── user.txt.erb
#   ├── product_support/
#   │   ├── system.txt.erb
#   │   └── user.txt.erb
#   └── escalation/
#       ├── system.txt.erb
#       └── user.txt.erb

require_relative "../lib/robot_lab"
require "erb"
require "ostruct"

# =============================================================================
# Template Renderer
# =============================================================================
# A simple ERB template renderer that mimics ruby_llm-template behavior.
# In production, use the actual ruby_llm-template gem.

class PromptTemplate
  attr_reader :template_dir

  def initialize(template_dir)
    @template_dir = template_dir
  end

  def render(template_name, **context)
    dir = File.join(@template_dir, template_name.to_s)

    {
      system: render_file(File.join(dir, "system.txt.erb"), context),
      user: render_file(File.join(dir, "user.txt.erb"), context)
    }
  end

  private

  def render_file(path, variables)
    return nil unless File.exist?(path)

    template = File.read(path)
    binding_obj = create_binding(variables)
    ERB.new(template, trim_mode: "-").result(binding_obj)
  end

  def create_binding(variables)
    # Convert all values to OpenStructs first, then create the namespace
    converted = variables.transform_values { |v| deep_to_ostruct(v) }
    namespace = OpenStruct.new(converted)
    # Use a clean binding without local variable pollution
    namespace.instance_exec { binding }
  end

  def deep_to_ostruct(obj)
    case obj
    when Hash
      OpenStruct.new(obj.transform_values { |v| deep_to_ostruct(v) })
    when Array
      obj.map { |item| deep_to_ostruct(item) }
    else
      obj
    end
  end
end

# =============================================================================
# Sample Data
# =============================================================================
# Simulated customer and business data that would come from your database.

COMPANY_NAME = "TechGear Pro"

SAMPLE_CUSTOMER = {
  name: "Sarah Johnson",
  email: "sarah.johnson@example.com",
  account_type: "Premium",
  member_since: "2022-03-15",
  vip: true,
  lifetime_value: 4_250.00,
  recent_orders: [
    { id: "ORD-2024-1847", date: "2024-01-10", status: "Delivered", total: 299.99 },
    { id: "ORD-2024-1923", date: "2024-01-15", status: "Processing", total: 149.50 }
  ],
  open_tickets: [
    { id: "TKT-5521", subject: "Delayed shipment inquiry", status: "Open" }
  ],
  purchase_history: [
    { category: "Electronics" },
    { category: "Accessories" },
    { category: "Audio" }
  ],
  escalation_history: []
}

CATEGORIES = [
  { name: "order", description: "Order status, shipping, returns, refunds" },
  { name: "product", description: "Product questions, specifications, recommendations" },
  { name: "escalation", description: "Complex issues, complaints, special requests" }
]

ORDERS = [
  {
    id: "ORD-2024-1847",
    date: "2024-01-10",
    status: "Delivered",
    total: 299.99,
    tracking: "1Z999AA10123456784",
    items: [
      { name: "Wireless Noise-Canceling Headphones", quantity: 1, price: 249.99 },
      { name: "Premium Carrying Case", quantity: 1, price: 49.99 }
    ]
  },
  {
    id: "ORD-2024-1923",
    date: "2024-01-15",
    status: "Processing",
    total: 149.50,
    tracking: nil,
    items: [
      { name: "USB-C Hub Pro", quantity: 1, price: 89.50 },
      { name: "Braided USB-C Cable 2m", quantity: 2, price: 30.00 }
    ]
  }
]

PRODUCTS = [
  {
    name: "Wireless Noise-Canceling Headphones XR500",
    sku: "AUDIO-XR500",
    price: 249.99,
    category: "Audio",
    in_stock: true,
    quantity: 45,
    features: ["40hr battery life", "Active noise cancellation", "Bluetooth 5.2", "Hi-Res Audio"],
    compatible_with: ["All Bluetooth devices", "3.5mm audio jack"]
  },
  {
    name: "USB-C Hub Pro 7-in-1",
    sku: "ACC-HUB7",
    price: 89.50,
    category: "Accessories",
    in_stock: true,
    quantity: 120,
    features: ["4K HDMI output", "100W Power Delivery", "SD/MicroSD slots", "USB 3.0 ports"],
    compatible_with: ["MacBook Pro", "MacBook Air", "iPad Pro", "Windows laptops"]
  }
]

PROMOTIONS = [
  { name: "New Year Sale", description: "15% off all audio products", code: "AUDIO15" },
  { name: "Free Shipping", description: "Free shipping on orders over $75", code: "FREESHIP" }
]

PRODUCT_CATEGORIES = [
  { name: "Electronics", description: "Laptops, tablets, smartphones" },
  { name: "Audio", description: "Headphones, speakers, microphones" },
  { name: "Accessories", description: "Cables, hubs, cases, chargers" }
]

POLICIES = {
  refund_window: 30,
  free_shipping_threshold: 75,
  express_fee: "$12.99"
}

ORDER_CAPABILITIES = [
  "Check order status and tracking",
  "Process returns and exchanges",
  "Issue refunds (up to $500 without manager approval)",
  "Modify pending orders",
  "Apply shipping upgrades"
]

ESCALATION_AUTHORITIES = [
  { name: "Courtesy Credit", description: "Account credit for inconvenience", limit: "$50" },
  { name: "Expedited Shipping", description: "Free upgrade to express shipping", limit: "Unlimited" },
  { name: "Extended Return Window", description: "Extend return period", limit: "60 days" },
  { name: "Price Match", description: "Match competitor pricing", limit: "20% max discount" }
]

# =============================================================================
# Main Demo
# =============================================================================

puts "=" * 70
puts "RobotLab + Prompt Templates Demo"
puts "E-Commerce Support Network with Dynamic Context"
puts "=" * 70
puts

# Configure RubyLLM
RubyLLM.configure do |config|
  config.anthropic_api_key = ENV.fetch("ANTHROPIC_API_KEY", nil)
end

# Initialize template renderer
template_dir = File.join(__dir__, "prompts")
templates = PromptTemplate.new(template_dir)

# Create model
model = RobotLab::RoboticModel.new("claude-sonnet-4", provider: :anthropic)

# -----------------------------------------------------------------------------
# Build Robots with Template-Generated Prompts
# -----------------------------------------------------------------------------

# Triage Robot - Uses dynamic system prompt based on customer context
triage_robot = RobotLab.build(
  name: "triage",
  description: "Classifies incoming requests to route to specialists",
  system: lambda { |network:|
    # Render template with current context
    rendered = templates.render(:triage,
      company_name: COMPANY_NAME,
      customer: SAMPLE_CUSTOMER,
      categories: CATEGORIES,
      message: network&.state&.data&.[](:current_message) || ""
    )
    rendered[:system]
  },
  model: model
)

# Order Support Robot
order_robot = RobotLab.build(
  name: "order",
  description: "Handles order-related inquiries with full order history",
  system: lambda { |network:|
    rendered = templates.render(:order_support,
      company_name: COMPANY_NAME,
      customer: SAMPLE_CUSTOMER,
      orders: ORDERS,
      policies: POLICIES,
      capabilities: ORDER_CAPABILITIES,
      message: network&.state&.data&.[](:current_message) || ""
    )
    rendered[:system]
  },
  model: model
)

# Product Support Robot
product_robot = RobotLab.build(
  name: "product",
  description: "Answers product questions with catalog knowledge",
  system: lambda { |network:|
    rendered = templates.render(:product_support,
      company_name: COMPANY_NAME,
      customer: SAMPLE_CUSTOMER,
      products: PRODUCTS,
      promotions: PROMOTIONS,
      product_categories: PRODUCT_CATEGORIES,
      message: network&.state&.data&.[](:current_message) || ""
    )
    rendered[:system]
  },
  model: model
)

# Escalation Robot
escalation_robot = RobotLab.build(
  name: "escalation",
  description: "Handles complex cases requiring special authority",
  system: lambda { |network:|
    context = {
      previous_interactions: [
        { date: "2024-01-12", channel: "Chat", summary: "Asked about order delay" },
        { date: "2024-01-14", channel: "Email", summary: "Followed up on shipping" }
      ],
      related_orders: ORDERS,
      compensation_history: [],
      escalation_reason: network&.state&.data&.[](:escalation_reason),
      sentiment: "Frustrated",
      urgency: "High"
    }

    rendered = templates.render(:escalation,
      company_name: COMPANY_NAME,
      customer: SAMPLE_CUSTOMER,
      authorities: ESCALATION_AUTHORITIES,
      context: context,
      message: network&.state&.data&.[](:current_message) || ""
    )
    rendered[:system]
  },
  model: model
)

# -----------------------------------------------------------------------------
# Create Network with Intelligent Routing
# -----------------------------------------------------------------------------

router = lambda do |args|
  # First call: run triage classifier
  return ["triage"] if args.call_count.zero?

  # Second call: route based on classification
  if args.call_count == 1
    classification = args.last_result&.output&.last&.content.to_s.downcase.strip

    category = case classification
               when /order/ then "order"
               when /product/ then "product"
               when /escalat/ then "escalation"
               else "escalation" # Default to escalation for unclear cases
               end

    args.network.state.data[:category] = category
    args.network.state.data[:classification_result] = classification
    return [category]
  end

  # After specialist responds, we're done
  nil
end

network = RobotLab.create_network(
  name: "ecommerce_support",
  robots: [triage_robot, order_robot, product_robot, escalation_robot],
  router: router,
  default_model: model,
  state: RobotLab.create_state(data: {
    current_message: nil,
    category: nil,
    classification_result: nil
  })
)

# -----------------------------------------------------------------------------
# Run Demo Scenarios
# -----------------------------------------------------------------------------

demo_queries = [
  {
    label: "Order Inquiry",
    message: "Where is my order ORD-2024-1923? It's been 5 days and still shows processing."
  },
  {
    label: "Product Question",
    message: "Are the XR500 headphones compatible with my iPhone? What's the battery life?"
  },
  {
    label: "Escalation Case",
    message: "This is ridiculous! I've been waiting 2 weeks for my order and nobody can help me. I want a refund AND compensation for this terrible experience!"
  }
]

demo_queries.each_with_index do |query, index|
  puts
  puts "-" * 70
  puts "Scenario #{index + 1}: #{query[:label]}"
  puts "-" * 70
  puts "Customer: #{query[:message]}"
  puts

  # Update state with current message
  state = RobotLab.create_state(data: {
    current_message: query[:message],
    category: nil,
    classification_result: nil
  })

  # Run the network
  result = network.run(query[:message], state: state)

  # Display results
  puts "Routing Decision: #{result.state.data[:category]&.upcase || 'N/A'}"
  puts "Classification: #{result.state.data[:classification_result]}"
  puts

  puts "Response Flow:"
  result.state.results.each_with_index do |robot_result, idx|
    puts
    puts "  #{idx + 1}. [#{robot_result.robot_name.upcase}]"
    robot_result.output.each do |msg|
      next unless msg.respond_to?(:content) && msg.content

      content = msg.content.to_s
      # Truncate long responses for display
      if content.length > 300
        puts "     #{content[0..300]}..."
      else
        puts "     #{content}"
      end
    end
  end

  puts
  puts "=" * 70
end

puts
puts "Demo Complete!"
puts
puts "This example demonstrates:"
puts "  - ERB templates for organized, reusable prompts"
puts "  - Dynamic context injection (customer data, order history, etc.)"
puts "  - Lambda-based system prompts that render at runtime"
puts "  - Multi-robot network with intelligent routing"
puts "  - State sharing between robots"
puts
puts "Template files are located in: #{template_dir}"
