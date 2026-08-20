#!/usr/bin/env ruby
# frozen_string_literal: true

# Example 6: Prompt Templates with prompt_manager
#
# Demonstrates using prompt_manager for organized, reusable prompts
# within a RobotLab network. This example shows an e-commerce support
# system with dynamic context injection using SimpleFlow's optional task routing.
#
# Usage:
#   ruby examples/06_prompt_templates.rb
#
# Template Structure (prompt_manager .md files with YAML front matter):
#   examples/prompts/
#   ├── triage.md
#   ├── order_support.md
#   ├── product_support.md
#   └── escalation.md

require_relative "common"

# =============================================================================
# Sample Data
# =============================================================================
# Simulated customer and business data that would come from your database.
# company_name is a template parameter (declared null in all four templates).
# AskUser gathers it from the user before building robots.

ask = RobotLab::AskUser.new
COMPANY_NAME = ask.call(
  "question" => "What is your company name?",
  "default"  => "TechGear Pro"
)

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
# Triage Robot with Routing Logic
# =============================================================================

# Custom triage robot that classifies and activates appropriate specialist
class TriageRobot < RobotLab::Robot
  def call(result)
    run_context = extract_run_context(result)
    message = run_context.delete(:message)
    robot_result = run(message, **run_context)

    new_result = result
      .with_context(@name.to_sym, robot_result)
      .continue(robot_result)

    # Examine LLM output and activate appropriate specialist
    classification = robot_result.reply.to_s.strip.downcase

    case classification
    when /order/
      new_result.activate(:order)
    when /product/
      new_result.activate(:product)
    when /escalat/
      new_result.activate(:escalation)
    else
      # Default to escalation for unclear cases
      new_result.activate(:escalation)
    end
  end
end

# =============================================================================
# Main Demo
# =============================================================================

banner "RobotLab + Prompt Templates Demo"
puts "E-Commerce Support Network with Dynamic Context"
puts

# Template path is set via ROBOT_LAB_TEMPLATE_PATH env var (see top of file)

# -----------------------------------------------------------------------------
# Build Robots with Template-Based Prompts
# -----------------------------------------------------------------------------

# Triage Robot - Classifies incoming requests
triage_robot = TriageRobot.new(
  name: "triage",
  description: "Classifies incoming requests to route to specialists",
  template: :triage,
  local_tools: [RobotLab::AskUser],
  context: {
    company_name: COMPANY_NAME,
    categories: CATEGORIES
  },
  **llm_opts
)

# Order Support Robot
order_robot = RobotLab.build(
  **llm_opts,
  name: "order",
  description: "Handles order-related inquiries with full order history",
  template: :order_support,
  local_tools: [RobotLab::AskUser],
  context: {
    company_name: COMPANY_NAME,
    policies: POLICIES,
    capabilities: ORDER_CAPABILITIES
  }
)

# Product Support Robot
product_robot = RobotLab.build(
  **llm_opts,
  name: "product",
  description: "Answers product questions with catalog knowledge",
  template: :product_support,
  local_tools: [RobotLab::AskUser],
  context: {
    company_name: COMPANY_NAME,
    products: PRODUCTS,
    promotions: PROMOTIONS,
    product_categories: PRODUCT_CATEGORIES
  }
)

# Escalation Robot
escalation_robot = RobotLab.build(
  **llm_opts,
  name: "escalation",
  description: "Handles complex cases requiring special authority",
  template: :escalation,
  local_tools: [RobotLab::AskUser],
  context: {
    company_name: COMPANY_NAME,
    authorities: ESCALATION_AUTHORITIES
  }
)

# -----------------------------------------------------------------------------
# Create Network with Optional Task Routing
# -----------------------------------------------------------------------------

# tools: :inherit on each task. Task#to_run_params forwards it to robot.run,
# which otherwise defaults to :none and would send the provider an empty tool
# list — the AskUser tool would be attached to each robot but never offered
# to the model.
network = RobotLab.create_network(name: "ecommerce_support") do
  task :triage, triage_robot, depends_on: :none, tools: :inherit
  task :order, order_robot, depends_on: :optional, tools: :inherit
  task :product, product_robot, depends_on: :optional, tools: :inherit
  task :escalation, escalation_robot, depends_on: :optional, tools: :inherit
end

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
  section "Scenario #{index + 1}: #{query[:label]}"
  puts "Customer: #{query[:message]}"
  puts

  # Run the network with context
  result = network.run(
    message: query[:message],
    customer: SAMPLE_CUSTOMER,
    orders: ORDERS
  )

  # Display triage classification
  if result.context[:triage]
    triage_result = result.context[:triage]
    puts "Classification: #{triage_result.reply}"
    puts
  end

  # Display specialist response (the final value)
  if result.value.is_a?(RobotLab::RobotResult)
    puts "Routed to: #{result.value.robot_name.upcase}"
    content = result.value.reply.to_s
    # Truncate long responses for display
    if content.length > 300
      puts "Response: #{content[0..300]}..."
    else
      puts "Response: #{content}"
    end
  end

  puts
  hr
end

puts
puts "Demo Complete!"
puts
puts <<~FOOTER
  This example demonstrates:
    - prompt_manager templates (.md with YAML front matter)
    - Build-time context (robot identity/capabilities)
    - Run-time context (customer data, order history)
    - Multi-robot network with optional task routing
    - SimpleFlow::Result for passing context between robots

  Template files are located in: #{File.join(__dir__, 'prompts')}
FOOTER
