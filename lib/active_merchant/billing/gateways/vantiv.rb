# frozen_string_literal: true
require "nokogiri"

module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    # Public: Vantiv gateway
    #
    # This gateway was previously known as `LitleGateway`. Vantiv bought Litle
    # in 2012. The URLs and the XML format (LitleXML) still reference the old
    # name.
    class VantivGateway < Gateway
      self.test_url = "https://www.testlitle.com/sandbox/communicator/online"
      self.live_url = "https://payments.litle.com/vap/communicator/online"

      self.supported_countries = ["US"]
      self.default_currency = "USD"
      self.supported_cardtypes = [
        :visa,
        :master,
        :american_express,
        :discover,
        :diners_club,
        :jcb
      ]

      self.homepage_url = "http://www.vantiv.com/"
      self.display_name = "Vantiv"

      AVS_RESPONSE_CODE = {
        "00" => "Y",
        "01" => "X",
        "02" => "D",
        "10" => "Z",
        "11" => "W",
        "12" => "A",
        "13" => "A",
        "14" => "P",
        "20" => "N",
        "30" => "S",
        "31" => "R",
        "32" => "U",
        "33" => "R",
        "34" => "I",
        "40" => "E"
      }.freeze

      CARD_TYPE = {
        "visa"             => "VI",
        "master"           => "MC",
        "american_express" => "AX",
        "discover"         => "DI",
        "jcb"              => "JC",
        "diners_club"      => "DC"
      }.freeze

      CHECK_TYPE = {
        "personal" => {
          "checking" => "Checking",
          "savings"  => "Savings"
        },
        "business" => {
          "checking" => "Corporate",
          "savings"  => "Corp Savings"
        }
      }.freeze

      DEFAULT_HEADERS = {
        "Content-Type" => "text/xml"
      }.freeze

      DEFAULT_REPORT_GROUP = "Default Report Group"

      ORDER_ID_MAX_LENGTH = 24

      POS_CAPABILITY = "magstripe"
      POS_ENTRY_MODE = "completeread"
      POS_CARDHOLDER_ID = "signature"

      RESPONSE_CODE_APPROVED = "000"
      RESPONSE_CODES_APPROVED = [
        "000", # approved
        "801", # account number registered
        "802" # account number previously registered
      ].freeze

      SCHEMA_VERSION = "9.4"

      SCRUBBED_PATTERNS = [
        %r((<user>).+(</user>)),
        %r((<password>).+(</password>)),
        %r((<number>).+(</number>)),
        %r((<cardValidationNum>).+(</cardValidationNum>)),
        %r((<accountNumber>).+(</accountNumber>)),
        %r((<paypageRegistrationId>).+(</paypageRegistrationId>)),
        %r((<authenticationValue>).+(</authenticationValue>))
      ].freeze

      SCRUBBED_REPLACEMENT = "\\1[FILTERED]\\2"

      SOURCE_APPLE_PAY = "applepay"
      SOURCE_RETAIL = "retail"
      SOURCE_ECOMMERCE = "ecommerce"

      VOID_TYPE_AUTHORIZATION = :authorization

      XML_NAMESPACE = "http://www.litle.com/schema"
      XML_REQUEST_ROOT = "litleOnlineRequest"
      XML_RESPONSE_NODES = %w[message response].freeze
      XML_RESPONSE_ROOT = "litleOnlineResponse"

      # Public: Object that represents a previous Vantiv response.
      #
      # Example:
      #   auth = ActiveMerchant::Billing::VantivGateway::Authorization.new(
      #     amount: 100,
      #     litle_txn_id: "100000000000000001",
      #     txn_type: :authorization
      #   )
      class Authorization
        attr_reader :amount, :litle_txn_id, :txn_type

        def initialize(amount: nil, litle_txn_id: nil, txn_type: nil)
          @amount = amount
          @litle_txn_id = litle_txn_id
          @txn_type = txn_type
        end

        def ==(other)
          amount == other.amount &&
            litle_txn_id == other.litle_txn_id &&
            txn_type == other.txn_type
        end
      end

      # Public: Vantiv eProtect registration object represents the values
      # returned from Vantiv as part of an eProtect request.
      #
      # Example:
      #  reg = ActiveMerchant::Billing::VantivGateway::Registration.new(
      #    "1234567890",
      #    month: "9",
      #    verification_value: "424",
      #    year: "2021"
      #  )
      class Registration
        attr_reader :id, :month, :verification_value, :year

        def initialize(id, month: "", verification_value: "", year: "")
          @id = id
          @month = month
          @verification_value = verification_value
          @year = year
        end
      end

      # Private: Simple object to contain gateway request details
      #
      # The Vantiv gateway has some inconsistent transaction and response
      # notes in the xml. This helps smooth those over and allows for
      # a simple helper to submit the request.
      class Request
        attr_reader :money, :response, :txn, :xml

        def initialize(money:, response:, txn:, xml:)
          @money = money
          @response = response
          @txn = txn
          @xml = xml
        end
      end

      # Public: Vantiv token object represents the tokenized credit card number
      # from Vantiv. Unlike other vault-like solutions, Vantiv only stores the
      # "account number".
      #
      # Example:
      #   token = ActiveMerchant::Billing::VantivGateway::Token.new(
      #     "1234567890",
      #     month: "9",
      #     verification_value: "424",
      #     year: "2021"
      #   )
      #
      # This is based on `PaymentToken` so all options are stored in the
      # metadata attribute.
      class Token < PaymentToken
        attr_reader :metadata

        alias litle_token payment_data

        # Private: Override initialize to specify required and optional params
        #
        # Keyword args makes it easier for callers to see what's expected.
        def initialize(token, month: "", verification_value: "", year: "")
          super(
            token,
            month: month,
            verification_value: verification_value,
            year: year
          )
        end

        def month
          metadata.fetch("month", "")
        end

        def verification_value
          metadata.fetch("verification_value", "")
        end

        def year
          metadata.fetch("year", "")
        end
      end

      # Private: Helpers for creating the Request XML required by Vantiv
      module RequestBuilderHelpers
        # Private: Add address elements common to billing and shipping
        def add_address(doc, address, person, options)
          doc.name(person[:name]) unless person[:name].blank?
          doc.firstName(person[:first_name]) unless person[:first_name].blank?
          doc.lastName(person[:last_name]) unless person[:last_name].blank?
          doc.addressLine1(address[:address1]) unless address[:address1].blank?
          doc.addressLine2(address[:address2]) unless address[:address2].blank?
          doc.city(address[:city]) unless address[:city].blank?
          doc.state(address[:state]) unless address[:state].blank?
          doc.zip(address[:zip]) unless address[:zip].blank?
          doc.country(address[:country]) unless address[:country].blank?
          doc.email(options[:email]) unless options[:email].blank?
          doc.phone(address[:phone]) unless address[:phone].blank?
        end

        # Private: Add billing address information
        #
        # The `billToAddress` element is always added
        def add_bill_to_address(doc, payment_method, options)
          address = options[:billing_address] || {}
          person = address_person(payment_method, address)

          doc.billToAddress do
            add_address(doc, address, person, options)
            doc.companyName(address[:company]) unless address[:company].blank?
          end
        end

        # Private: Add the custom billing descriptor
        def add_custom_billing(doc, options)
          name = options[:descriptor_name]
          phone = options[:descriptor_phone]

          return unless name || phone

          doc.customBilling do
            doc.phone(options[:descriptor_phone]) if phone
            doc.descriptor(options[:descriptor_name]) if name
          end
        end

        # Private: Add shipping address information
        def add_ship_to_address(doc, options)
          address = options[:shipping_address]
          return if address.blank?

          # Shipping address only accepts `name`
          person = { name: address[:name] }

          doc.shipToAddress do
            add_address(doc, address, person, options)
          end
        end

        # Private: Add truncated order id
        def add_order_id(doc, options)
          doc.orderId(truncate(options[:order_id], ORDER_ID_MAX_LENGTH))
        end

        # Private: Add order id with default
        def add_order_source(doc, options)
          doc.orderSource(options[:order_source].presence || SOURCE_ECOMMERCE)
        end

        # Private: Determine person name attributes for an address
        def address_person(payment_method, address)
          payment = {}

          {}.tap do |person|
            %i[name first_name last_name].each do |attribute|
              # Get value from payment method if possible
              if payment_method.respond_to?(:name)
                payment[attribute] = payment_method.public_send(attribute)
              end

              # Payment method information takes precendence over address
              person[attribute] = payment[attribute].presence ||
                                  address[attribute]
            end
          end
        end

        # Private: Build the xml request and add authentication before yielding
        def build_authenticated_xml_request
          build_xml_request do |doc|
            doc.authentication do
              doc.user(@options[:login])
              doc.password(@options[:password])
            end
            yield(doc)
          end
        end

        # Private: Build and yield a simple xml builder `doc`
        def build_xml_request
          builder = Nokogiri::XML::Builder.new
          builder.public_send(XML_REQUEST_ROOT, root_attributes) do |doc|
            yield(doc)
          end
          builder.doc.root.to_xml
        end

        # Private: Helper method to format the expiration date
        def exp_date(payment_method)
          formatted_month = format(payment_method.month, :two_digits)
          formatted_year = format(payment_method.year, :two_digits)

          "#{formatted_month}#{formatted_year}"
        end

        # Private: Hash of default root attributes for the xml document
        def root_attributes
          {
            merchantId: @options[:merchant_id],
            version: SCHEMA_VERSION,
            xmlns: XML_NAMESPACE
          }
        end

        # Private: Helper method to create the transaction attrs for a request
        def transaction_attributes(options)
          attributes = {}
          attributes[:id] = truncate(options[:id] ||
                                     options[:order_id], ORDER_ID_MAX_LENGTH)
          attributes[:reportGroup] = options[:merchant] || DEFAULT_REPORT_GROUP
          attributes[:customerId] = options[:customer]
          attributes.delete_if { |_key, value| value.nil? }
          attributes
        end
      end

      # Private: Builds and returns a `Request` object to be submitted to
      # the gateway.
      class RequestBuilder
        include RequestBuilderHelpers

        attr_reader :gateway

        def initialize(gateway)
          @gateway = gateway
          # shim so it works with modules
          @options = gateway_options
        end

        # Public: Gateway supported actions
        #
        # Subclasses will implement supported actions for that type
        [
          :authorize,
          :capture,
          :credit,
          :purchase,
          :refund,
          :store,
          :void
        ].each do |action|
          define_method(action) do
            _not_supported
          end
        end

      private

        # Private: Build the xml request with the correct root node and attrs
        def build_request(txn,
                          response: nil,
                          money: nil,
                          order_id: true,
                          options: {})
          xml = build_authenticated_xml_request do |doc|
            doc.public_send(txn, transaction_attributes(options)) do
              add_order_id(doc, options) if order_id
              yield(doc)
            end
          end

          # Use the transaction if response not specified
          response = response.presence || txn
          Request.new(txn: txn, response: response, money: money, xml: xml)
        end

        # Private: Helper method to access the gateway options
        def gateway_options
          gateway.instance_variable_get("@options") || {}
        end

        # Private: Helper method to raise an exception for an unsupported action
        def not_supported
          fail NotImplementedError, "gateway action not supported"
        end

        ## Private: Shim helper methods from the `gateway`
        def format(*args)
          gateway.send(:format, *args)
        end

        def truncate(*args)
          gateway.send(:truncate, *args)
        end
      end

      # Private: Request builder for `Authorization` requests
      #
      # Implements supported *actions* for this type of request
      class AuthorizationRequestBuilder < RequestBuilder
        # Public: capture
        def capture(money, payment_method, options = {})
          build_request(:capture,
                        money: money,
                        order_id: false,
                        options: options) do |doc|
            doc.litleTxnId(payment_method.litle_txn_id)
            doc.amount(money) if money.present?
          end
        end

        # Public: refund
        def refund(money, payment_method, options = {})
          type = refund_type(payment_method.txn_type)

          build_request(type,
                        money: money,
                        order_id: false,
                        options: options) do |doc|
            doc.litleTxnId(payment_method.litle_txn_id)
            doc.amount(money) if money.present?
            add_custom_billing(doc, options)
          end
        end

        # Public: void
        def void(payment_method, options = {})
          type = void_type(payment_method.txn_type)

          build_request(type, order_id: false, options: options) do |doc|
            doc.litleTxnId(payment_method.litle_txn_id)
            money = options[:amount].presence || payment_method.amount
            doc.amount(money) if type == :authReversal
          end
        end

      private

        # Private: Determine the type of `refund`
        def refund_type(kind)
          kind == :echeckSales ? :echeckCredit : :credit
        end

        # Private: Determine the type of `void`
        def void_type(kind)
          case kind
          when VOID_TYPE_AUTHORIZATION
            :authReversal
          when :echeckSales, :echeckCredit
            :echeckVoid
          else
            :void
          end
        end
      end

      # Private: Request builder for `Check` requests
      #
      # Implements supported *actions* for this type of request
      class CheckRequestBuilder < RequestBuilder
        # Public: purchase
        def purchase(money, payment_method, options = {})
          build_request(:echeckSale,
                        response: :echeckSales,
                        money: money,
                        options: options) do |doc|
            doc.amount(money)
            add_order_source(doc, options)
            add_bill_to_address(doc, payment_method, options)
            add_ship_to_address(doc, options)
            add_echeck(doc, payment_method)
            add_custom_billing(doc, options)
          end
        end

        # Public: refund
        def refund(money, payment_method, options = {})
          build_request(:echeckCredit, money: money, options: options) do |doc|
            doc.amount(money)
            add_order_source(doc, options)
            add_bill_to_address(doc, payment_method, options)
            add_echeck(doc, payment_method)
            add_custom_billing(doc, options)
          end
        end

        # Public: store
        def store(payment_method, options = {})
          build_request(:registerTokenRequest,
                        response: :registerToken,
                        options: options) do |doc|
            doc.echeckForToken do
              doc.accNum(payment_method.account_number)
              doc.routingNum(payment_method.routing_number)
            end
          end
        end

      private

        # Private: Add `echeck` node to doc
        def add_echeck(doc, payment_method)
          doc.echeck do
            holder_type = payment_method.account_holder_type
            account_type = payment_method.account_type
            doc.accType(CHECK_TYPE[holder_type][account_type])
            doc.accNum(payment_method.account_number)
            doc.routingNum(payment_method.routing_number)

            check_number = payment_method.number
            doc.checkNum(check_number) if check_number.present?
          end
        end
      end

      # Private: Request builder for `CreditCard` requests
      #
      #
      # Implements supported *actions* for this type of request
      # Note: `NetworkTokenizationCreditCard` are also supported here
      class CreditCardRequestBuilder < RequestBuilder
        # Public: authorize
        def authorize(money, payment_method, options = {})
          build_request(:authorization, money: money, options: options) do |doc|
            doc.amount(money)
            add_order_source(doc, payment_method, options)
            add_bill_to_address(doc, payment_method, options)
            add_ship_to_address(doc, options)
            add_card(doc, payment_method)
            add_cardholder_authentication(doc, payment_method)
            add_pos(doc, payment_method)
            add_custom_billing(doc, options)
            add_debt_repayment(doc, options)
          end
        end

        # Public: purchase
        def purchase(money, payment_method, options = {})
          build_request(:sale, money: money, options: options) do |doc|
            doc.amount(money)
            add_order_source(doc, payment_method, options)
            add_bill_to_address(doc, payment_method, options)
            add_ship_to_address(doc, options)
            add_card(doc, payment_method)
            add_cardholder_authentication(doc, payment_method)
            add_custom_billing(doc, options)
            add_pos(doc, payment_method)
            add_debt_repayment(doc, options)
          end
        end

        # Public: refund
        def refund(money, payment_method, options = {})
          build_request(:credit, money: money, options: options) do |doc|
            doc.amount(money)
            add_order_source(doc, payment_method, options)
            add_bill_to_address(doc, payment_method, options)
            add_card(doc, payment_method)
            add_custom_billing(doc, options)
            add_pos(doc, payment_method)
          end
        end

        # Public: store
        def store(payment_method, options = {})
          build_request(:registerTokenRequest,
                        response: :registerToken,
                        options: options) do |doc|
            doc.accountNumber(payment_method.number)
            if payment_method.verification_value
              doc.cardValidationNum(payment_method.verification_value)
            end
          end
        end

      private

        # Private: Add the `card` node
        def add_card(doc, payment_method)
          doc.card do
            if payment_method_has_track_data?(payment_method)
              doc.track(payment_method.track_data)
            else
              doc.type_(CARD_TYPE[payment_method.brand])
              doc.number(payment_method.number)
              doc.expDate(exp_date(payment_method))
              doc.cardValidationNum(payment_method.verification_value)
            end
          end
        end

        # Private: Add the authentication data to support tokenized cards
        def add_cardholder_authentication(doc, payment_method)
          return unless payment_method.is_a?(NetworkTokenizationCreditCard)

          doc.cardholderAuthentication do
            doc.authenticationValue(payment_method.payment_cryptogram)
          end
        end

        # Private: Add the `debtRepayment` node
        def add_debt_repayment(doc, options)
          doc.debtRepayment(true) if options[:debt_repayment] == true
        end

        # Private: Add the `orderSource` node based on payment method
        def add_order_source(doc, payment_method, options)
          order_source = options[:order_source].presence

          if payment_method.respond_to?(:source) &&
             payment_method.source == :apple_pay
            order_source ||= SOURCE_APPLE_PAY
          end

          order_source ||= if payment_method_has_track_data?(payment_method)
                             SOURCE_RETAIL
                           else
                             SOURCE_ECOMMERCE
                           end

          doc.orderSource(order_source)
        end

        # Private: Add point of sale information
        def add_pos(doc, payment_method)
          return unless payment_method_has_track_data?(payment_method)

          doc.pos do
            doc.capability(POS_CAPABILITY)
            doc.entryMode(POS_ENTRY_MODE)
            doc.cardholderId(POS_CARDHOLDER_ID)
          end
        end

        # Private: Helper to determine if the payment method has track data
        def payment_method_has_track_data?(payment_method)
          payment_method.respond_to?(:track_data) &&
            payment_method.track_data.present?
        end
      end

      # Private: Request builder for `Registration` requests
      #
      # Implements supported *actions* for this type of request
      class RegistrationRequestBuilder < RequestBuilder
        # Public: authorize
        def authorize(money, payment_method, options = {})
          build_request(:authorization, money: money, options: options) do |doc|
            doc.amount(money)
            add_order_source(doc, options)
            add_bill_to_address(doc, payment_method, options)
            add_ship_to_address(doc, options)
            add_paypage(doc, payment_method)
            add_custom_billing(doc, options)
          end
        end

        # Public: purchase
        def purchase(money, payment_method, options = {})
          build_request(:sale, money: money, options: options) do |doc|
            doc.amount(money)
            add_order_source(doc, options)
            add_bill_to_address(doc, payment_method, options)
            add_ship_to_address(doc, options)
            add_paypage(doc, payment_method)
            add_custom_billing(doc, options)
          end
        end

        # Public: refund
        def refund(money, payment_method, options = {})
          build_request(:credit, money: money, options: options) do |doc|
            doc.amount(money)
            add_order_source(doc, options)
            add_bill_to_address(doc, payment_method, options)
            add_paypage(doc, payment_method)
            add_custom_billing(doc, options)
          end
        end

        # Public: store
        def store(payment_method, options = {})
          build_request(:registerTokenRequest,
                        response: :registerToken,
                        options: options) do |doc|
            doc.paypageRegistrationId(payment_method.id)
          end
        end

      private

        # Private: Add the registration node
        def add_paypage(doc, payment_method)
          doc.paypage do
            doc.paypageRegistrationId(payment_method.id)

            expiration = exp_date(payment_method)
            doc.expDate(expiration) if expiration.present?

            cvv = payment_method.verification_value
            doc.cardValidationNum(cvv) if cvv.present?
          end
        end
      end

      # Private: Request builder for `Token` requests
      class TokenRequestBuilder < RequestBuilder
        # Public: authorize
        def authorize(money, payment_method, options = {})
          build_request(:authorization, money: money, options: options) do |doc|
            doc.amount(money)
            add_order_source(doc, options)
            add_bill_to_address(doc, payment_method, options)
            add_ship_to_address(doc, options)
            add_token(doc, payment_method)
            add_custom_billing(doc, options)
          end
        end

        # Public: purchase
        def purchase(money, payment_method, options = {})
          build_request(:sale, money: money, options: options) do |doc|
            doc.amount(money)
            add_order_source(doc, options)
            add_bill_to_address(doc, payment_method, options)
            add_ship_to_address(doc, options)
            add_token(doc, payment_method)
            add_custom_billing(doc, options)
          end
        end

        # Public: refund
        def refund(money, payment_method, options = {})
          build_request(:credit, money: money, options: options) do |doc|
            doc.amount(money)
            add_order_source(doc, options)
            add_bill_to_address(doc, payment_method, options)
            add_token(doc, payment_method)
            add_custom_billing(doc, options)
          end
        end

      private

        # Private: Add the `token` node
        def add_token(doc, payment_method)
          doc.token do
            token = payment_method.litle_token
            doc.litleToken(token) if token.present?

            expiration = exp_date(payment_method)
            doc.expDate(expiration) if expiration.present?

            cvv = payment_method.verification_value
            doc.cardValidationNum(cvv) if cvv.present?
          end
        end
      end

      # Public: Create a new Vantiv gateway.
      #
      # options - A hash of options:
      #           :login         - The user.
      #           :password      - The password.
      #           :merchant_id   - The merchant id.
      def initialize(options = {})
        requires!(options, :login, :password, :merchant_id)
        super

        # Simple registry to map payment method types to request builders
        # See: `requests` method for lookup
        @request_builders = {
          Authorization => AuthorizationRequestBuilder.new(self),
          Check => CheckRequestBuilder.new(self),
          CreditCard => CreditCardRequestBuilder.new(self),
          NetworkTokenizationCreditCard => CreditCardRequestBuilder.new(self),
          Registration => RegistrationRequestBuilder.new(self),
          Token => TokenRequestBuilder.new(self)
        }
      end

      # Public: Authorize that a customer has submitted a valid payment method
      # and that they have sufficient funds for the transation.
      def authorize(money, payment_method, options = {})
        request = requests(payment_method).authorize(
          money,
          payment_method,
          options
        )

        submit_request(request)
      end

      # Public: Capture the referenced authorization transaction to transfer
      # funds from the customer to the merchant.
      def capture(money, authorization, options = {})
        request = requests(authorization).capture(
          money,
          authorization,
          options
        )

        submit_request(request)
      end

      # [DEPRECATED] Public: Refund money to a customer.
      #
      #  See `#refund`
      def credit(money, authorization, options = {})
        ActiveMerchant.deprecated CREDIT_DEPRECATION_MESSAGE
        refund(money, authorization, options)
      end

      # Public: A single transaction to authorize and transfer funds from
      # the customer to the merchant.
      def purchase(money, payment_method, options = {})
        request = requests(payment_method).purchase(
          money,
          payment_method,
          options
        )

        submit_request(request)
      end

      # Public: Refund money to a customer.
      def refund(money, payment_method, options = {})
        request = requests(payment_method).refund(
          money,
          payment_method,
          options
        )

        submit_request(request)
      end

      # Public: Scrub text for sensitive values.
      #
      # See `SCRUBBED_PATTERNS` above.
      def scrub(transcript)
        SCRUBBED_PATTERNS.inject(transcript) do |text, pattern|
          text.gsub(pattern, SCRUBBED_REPLACEMENT)
        end
      end

      # Public: Submit a payment method and receive a Vantiv token in return.
      def store(payment_method, options = {})
        request = requests(payment_method).store(
          payment_method,
          options
        )

        submit_request(request)
      end

      # Public: Indicates if this gateway supports scrubbing.
      #
      # See `#scrub`
      def supports_scrubbing?
        true
      end

      # Public: Verify a customer's payment method by performing an
      # authorize and void.
      #
      # Note: This isn't a supported gateway function - it is a combination
      # of two actions. The `authorize` action must support the payment
      # method in order for this to work.
      #
      # Vantiv transactions: `authorize` + `void`
      def verify(payment_method, options = {})
        MultiResponse.run(:use_first_response) do |r|
          r.process { authorize(0, payment_method, options) }
          r.process(:ignore_result) { void(r.authorization, options) }
        end
      end

      # Public: Void (cancel) a transaction that occurred during the same
      # business day.
      #
      # Vantiv supports `void` transactions for:
      #  * `capture`
      #  * `credit` (refund)
      #  * `sale`
      #
      # This action checks if the `authorization` param is for an `authorize`
      # action. If so, an `authReversal` is submitted.
      #
      # Vantiv transaction: `void` or `authReversal`
      def void(authorization, options = {})
        request = requests(authorization).void(
          authorization,
          options
        )

        submit_request(request)
      end

    private

      # Private: Create `Authorization` from the parsed response
      def authorization_from(kind, parsed, money)
        if kind == :registerToken
          parsed[:litleToken]
        else
          Authorization.new(
            amount: money,
            litle_txn_id: parsed[:litleTxnId],
            txn_type: kind
          )
        end
      end

      # Private: Commit request data to Vantiv gateway and return a `Response`
      def commit(kind, request, money = nil)
        parsed = parse(kind, ssl_post(url, request, DEFAULT_HEADERS))

        options = {
          authorization: authorization_from(kind, parsed, money),
          test: test?,
          avs_result: {
            code: AVS_RESPONSE_CODE[parsed[:fraudResult_avsResult]]
          },
          cvv_result: parsed[:fraudResult_cardValidationResult]
        }

        Response.new(
          success_from(kind, parsed),
          parsed[:message],
          parsed,
          options
        )
      end

      # Private: Parse the response from the Vantiv gateway into a Hash
      def parse(kind, xml)
        parsed = {}

        doc = Nokogiri::XML(xml).remove_namespaces!
        doc.xpath("//#{XML_RESPONSE_ROOT}/#{kind}Response/*").each do |node|
          if node.elements.empty?
            parsed[node.name.to_sym] = node.text
          else
            node.elements.each do |childnode|
              name = "#{node.name}_#{childnode.name}"
              parsed[name.to_sym] = childnode.text
            end
          end
        end

        if parsed.empty?
          XML_RESPONSE_NODES.each do |attribute|
            parsed[attribute.to_sym] = doc
                                       .xpath("//#{XML_RESPONSE_ROOT}")
                                       .attribute(attribute)
                                       .value
          end
        end

        parsed
      end

      # Private: Lookup up a request builder based on the class of the object
      def requests(type)
        @request_builders[type.class]
      end

      # Private: Submit a `Request` to Vantiv gateway via the `commit` method
      def submit_request(request)
        commit(request.response, request.xml, request.money)
      end

      # Private: Determine if the response was a success
      def success_from(kind, parsed)
        approved = (parsed[:response] == RESPONSE_CODE_APPROVED)
        return approved unless kind == :registerToken

        RESPONSE_CODES_APPROVED.include?(parsed[:response])
      end

      # Private: Return the correct URL based on the gateway options
      def url
        return @options[:url] if @options[:url].present?

        test? ? test_url : live_url
      end
    end
  end
end
