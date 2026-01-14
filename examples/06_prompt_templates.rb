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

# Configure RobotLab
RobotLab.configure do |config|
  config.anthropic_api_key = ENV.fetch("ANTHROPIC_API_KEY", nil)
  config.template_path = File.join(__dir__, "prompts")
end

# -----------------------------------------------------------------------------
# Build Robots with Template-Based Prompts
# -----------------------------------------------------------------------------

# Triage Robot - Classifies incoming requests
triage_robot = RobotLab.build(
  name: "triage",
  description: "Classifies incoming requests to route to specialists",
  template: :triage,
  context: {
    company_name: COMPANY_NAME,
    categories: CATEGORIES
  },
  model: "claude-sonnet-4"
)

# Order Support Robot
order_robot = RobotLab.build(
  name: "order",
  description: "Handles order-related inquiries with full order history",
  template: :order_support,
  context: {
    company_name: COMPANY_NAME,
    policies: POLICIES,
    capabilities: ORDER_CAPABILITIES
  },
  model: "claude-sonnet-4"
)

# Product Support Robot
product_robot = RobotLab.build(
  name: "product",
  description: "Answers product questions with catalog knowledge",
  template: :product_support,
  context: {
    company_name: COMPANY_NAME,
    products: PRODUCTS,
    promotions: PROMOTIONS,
    product_categories: PRODUCT_CATEGORIES
  },
  model: "claude-sonnet-4"
)

# Escalation Robot
escalation_robot = RobotLab.build(
  name: "escalation",
  description: "Handles complex cases requiring special authority",
  template: :escalation,
  context: {
    company_name: COMPANY_NAME,
    authorities: ESCALATION_AUTHORITIES
  },
  model: "claude-sonnet-4"
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
  state: RobotLab.create_state(data: {
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

  # Run the network with context
  result = network.run(
    message: query[:message],
    customer: SAMPLE_CUSTOMER,
    orders: ORDERS
  )

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
puts "  - ruby_llm-template for organized, reusable prompts"
puts "  - Build-time context (robot identity/capabilities)"
puts "  - Run-time context (customer data, order history)"
puts "  - Multi-robot network with intelligent routing"
puts "  - State sharing between robots"
puts
puts "Template files are located in: #{File.join(__dir__, 'prompts')}"
