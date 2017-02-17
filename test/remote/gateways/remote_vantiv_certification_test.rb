require 'test_helper'

class RemoteVantivCertification < Test::Unit::TestCase
  TXN_PROCESSING_TIME = 5 # seconds

  def setup
    Base.mode = :test
    @gateway = VantivGateway.new(fixtures(:vantiv).merge(:url => "https://prelive.litle.com/vap/communicator/online"))
  end

  ### Order Ids 1 through 9 - Authorization certification tests
  def test1
    credit_card = CreditCard.new(
      :number => '4457010000000009',
      :month => '01',
      :year => '2021',
      :verification_value => '349',
      :brand => 'visa'
    )

    options = {
      :order_id => '1',
      :billing_address => {
        :name => 'John & Mary Smith',
        :address1 => '1 Main St.',
        :city => 'Burlington',
        :state => 'MA',
        :zip => '01803-3747',
        :country => 'US'
      }
    }

    auth_assertions(10010, credit_card, options, :avs => "X", :cvv => "M")

    # 1: authorize avs
    authorize_avs_assertions(credit_card, options, :avs => "X", :cvv => "M")

    sale_assertions(10010, credit_card, options, :avs => "X", :cvv => "M")
  end

  def test2
    credit_card = CreditCard.new(:number => '5112010000000003', :month => '02',
                                 :year => '2021', :brand => 'master',
                                 :verification_value => '261')

    options = {
      :order_id => '2',
      :billing_address => {
        :name => 'Mike J. Hammer',
        :address1 => '2 Main St.',
        :city => 'Riverside',
        :state => 'RI',
        :zip => '02915',
        :country => 'US'
      }
    }

    auth_assertions(20020, credit_card, options, :avs => "Z", :cvv => "M")

    # 2: authorize avs
    authorize_avs_assertions(credit_card, options, :avs => "Z", :cvv => "M")

    sale_assertions(20020, credit_card, options, :avs => "Z", :cvv => "M")
  end

  def test3
    credit_card = CreditCard.new(
      :number => '6011010000000003',
      :month => '03',
      :year => '2021',
      :verification_value => '758',
      :brand => 'discover'
    )

    options = {
      :order_id => '3',
      :billing_address => {
        :name => 'Eileen Jones',
        :address1 => '3 Main St.',
        :city => 'Bloomfield',
        :state => 'CT',
        :zip => '06002',
        :country => 'US'
      }
    }
    auth_assertions(30030, credit_card, options, :avs => "Z", :cvv => "M")

    # 3: authorize avs
    authorize_avs_assertions(credit_card, options, :avs => "Z", :cvv => "M")

    sale_assertions(30030, credit_card, options, :avs => "Z", :cvv => "M")
  end

  def test4
    credit_card = CreditCard.new(
      :number => '375001000000005',
      :month => '04',
      :year => '2021',
      :brand => 'american_express'
    )

    options = {
      :order_id => '4',
      :billing_address => {
        :name => 'Bob Black',
        :address1 => '4 Main St.',
        :city => 'Laurel',
        :state => 'MD',
        :zip => '20708',
        :country => 'US'
      }
    }

    auth_assertions(40040, credit_card, options, :avs => "A", :cvv => nil)

    # 4: authorize avs
    authorize_avs_assertions(credit_card, options, :avs => "A")

    sale_assertions(40040, credit_card, options, :avs => "A", :cvv => nil)
  end

  def test5
    credit_card = NetworkTokenizationCreditCard.new(
      brand: "visa",
      month: "05",
      number: "4100200300011001",
      payment_cryptogram: "BwABBJQ1AgAAA AAgJDUCAAAAAA A=",
      verification_value: "463",
      year: "2021"
    )

    options = {
      order_id: "5"
    }

    auth_assertions(10100, credit_card, options, avs: "U", cvv: "M", auth_code: "55555")

    # 5: authorize avs
    authorize_avs_assertions(credit_card, options, avs: "U", cvv: "M")

    sale_assertions(10100, credit_card, options, avs: "U", cvv: "M")
  end

  def test6
    credit_card = CreditCard.new(:number => '4457010100000008', :month => '06',
                                 :year => '2021', :brand => 'visa',
                                 :verification_value => '992')

    options = {
      :order_id => '6',
      :billing_address => {
        :name => 'Joe Green',
        :address1 => '6 Main St.',
        :city => 'Derry',
        :state => 'NH',
        :zip => '03038',
        :country => 'US'
      }
    }

    # 6: authorize
    assert response = @gateway.authorize(60060, credit_card, options)
    assert !response.success?
    assert_equal '110', response.params['response']
    assert_equal 'Insufficient Funds', response.message
    assert_equal "I", response.avs_result["code"]
    assert_equal "P", response.cvv_result["code"]

    # 6. sale
    assert response = @gateway.purchase(60060, credit_card, options)
    assert !response.success?
    assert_equal '110', response.params['response']
    assert_equal 'Insufficient Funds', response.message
    assert_equal "I", response.avs_result["code"]
    assert_equal "P", response.cvv_result["code"]

    # 6A. void
    assert response = @gateway.void(response.authorization, {:order_id => '6A'})
    assert_equal '360', response.params['response']
    assert_equal 'No transaction found with specified litleTxnId', response.message
  end

  def test7
    credit_card = CreditCard.new(:number => '5112010100000002', :month => '07',
                                 :year => '2021', :brand => 'master',
                                 :verification_value => '251')

    options = {
      :order_id => '7',
      :billing_address => {
        :name => 'Jane Murray',
        :address1 => '7 Main St.',
        :city => 'Amesbury',
        :state => 'MA',
        :zip => '01913',
        :country => 'US'
      }
    }

    # 7: authorize
    assert response = @gateway.authorize(70070, credit_card, options)
    assert !response.success?
    assert_equal '301', response.params['response']
    assert_equal 'Invalid Account Number', response.message
    assert_equal "I", response.avs_result["code"]
    assert_equal "N", response.cvv_result["code"]

    # 7: authorize avs
    authorize_avs_assertions(credit_card, options, :avs => "I", :cvv => "N", :message => "Invalid Account Number", :success => false)

    # 7. sale
    assert response = @gateway.purchase(70070, credit_card, options)
    assert !response.success?
    assert_equal '301', response.params['response']
    assert_equal 'Invalid Account Number', response.message
    assert_equal "I", response.avs_result["code"]
    assert_equal "N", response.cvv_result["code"]
  end

  def test8
    credit_card = CreditCard.new(:number => '6011010100000002', :month => '08',
                                 :year => '2021', :brand => 'discover',
                                 :verification_value => '184')

    options = {
      :order_id => '8',
      :billing_address => {
        :name => 'Mark Johnson',
        :address1 => '8 Main St.',
        :city => 'Manchester',
        :state => 'NH',
        :zip => '03101',
        :country => 'US'
      }
    }

    # 8: authorize
    assert response = @gateway.authorize(80080, credit_card, options)
    assert !response.success?
    assert_equal '123', response.params['response']
    assert_equal 'Call Discover', response.message
    assert_equal "I", response.avs_result["code"]
    assert_equal "P", response.cvv_result["code"]

    # 8: authorize avs
    authorize_avs_assertions(credit_card, options, :avs => "I", :cvv => "P", :message => "Call Discover", :success => false)

    # 8: sale
    assert response = @gateway.purchase(80080, credit_card, options)
    assert !response.success?
    assert_equal '123', response.params['response']
    assert_equal 'Call Discover', response.message
    assert_equal "I", response.avs_result["code"]
    assert_equal "P", response.cvv_result["code"]
  end

  def test9
    credit_card = CreditCard.new(:number => '375001010000003', :month => '09',
                                 :year => '2021', :brand => 'american_express',
                                 :verification_value => '0421')

    options = {
      :order_id => '9',
      :billing_address => {
        :name => 'James Miller',
        :address1 => '9 Main St.',
        :city => 'Boston',
        :state => 'MA',
        :zip => '02134',
        :country => 'US'
      }
    }

    # 9: authorize
    assert response = @gateway.authorize(90090, credit_card, options)

    assert !response.success?
    assert_equal '303', response.params['response']
    assert_equal 'Pick Up Card', response.message
    assert_equal "I", response.avs_result["code"]

    # 9: authorize avs
    authorize_avs_assertions(credit_card, options, :avs => "I", :message => "Pick Up Card", :success => false)

    # 9: sale
    assert response = @gateway.purchase(90090, credit_card, options)
    assert !response.success?
    assert_equal '303', response.params['response']
    assert_equal 'Pick Up Card', response.message
    assert_equal "I", response.avs_result["code"]
  end

  ### Order Ids 10 through 13 - Partial Authorization certification tests
  ## Not Implemented - Required if you plan to use Partial Authorizations

  ### Order Ids 14 through 20 - Prepaid Indicator certification tests
  ## Not Implemented - Required if you plan to receive Prepaid Indicators

  ### Order Ids 21 through 24 - Affluence Indicators certification tests
  ## Not Implemented - Required if you plan to receive Affluence Indicators

  ### Order Id 25 - Issuer Country certification test
  ## Not Implemented - Required if you plan to receive Issuer Country info

  ### Order Ids 26 through 31 - Healthcare Card (IIAS) certification tests
  ## Not Implemented - Required if you plan to use Healthcare (IIAS) cards

  ### Authorization Recycling Advice certification tests
  ## Not Implemented - Required if you plan to receive Auth Recycling Advice

  ### Order Ids 32 through 36 - Authorization Reversal certification tests
  def test32
    credit_card = CreditCard.new(
      brand: "visa",
      month: "01",
      number: "4457010000000009",
      verification_value: "349",
      year: "2021"
    )

    options = {
      order_id: "32",
      billing_address: {
        address1: "1 Main St.",
        city: "Burlington",
        country: "US",
        name: "John Smith",
        state: "MA",
        zip: "01803-3747"
      }
    }

    # 32: Authorization
    auth_response = @gateway.authorize(10010, credit_card, options)

    assert_equal "000", auth_response.params["response"]
    assert_equal "Approved", auth_response.message
    assert_equal "X", auth_response.avs_result["code"]
    assert_equal "M", auth_response.cvv_result["code"]
    assert_equal "11111", auth_response.params["authCode"].strip

    # 32A: Capture
    capture_response = @gateway.capture(5050, auth_response.authorization)

    assert_equal "000", capture_response.params["response"]
    assert_equal "Approved", capture_response.message

    # 32B fails intermittently if capture does not have enough time to process
    sleep(TXN_PROCESSING_TIME)

    # 32B: Authorization Reversal
    reversal_response = @gateway.void(auth_response.authorization)

    assert_equal "111", reversal_response.params["response"]
    assert_equal "Authorization amount has already been depleted", reversal_response.message
  end

  def test33
    credit_card = NetworkTokenizationCreditCard.new(
      brand: "master",
      name: "Mike J. Hammer",
      month: "02",
      number: "5112010000000003",
      payment_cryptogram: "BwABBJQ1AgAAA AAgJDUCAAAAAA A=",
      verification_value: "261",
      year: "2021"
    )

    options = {
      billing_address: {
        address1: "2 Main St.",
        address2: "Apt. 222",
        city: "Riverside",
        country: "US",
        state: "RI",
        zip: "02915"
      },
      order_id: "33"
    }

    # 33: Authorization
    auth_response = @gateway.authorize(20020, credit_card, options)

    assert_equal "000", auth_response.params["response"]
    assert_equal "Approved", auth_response.message
    assert_equal "22222", auth_response.params["authCode"].strip
    assert_equal "Z", auth_response.avs_result["code"]
    assert_equal "M", auth_response.cvv_result["code"]

    # 33A: Authorization Reversal
    reversal_response = @gateway.void(auth_response.authorization)

    assert_equal "000", reversal_response.params["response"]
    assert_equal "Approved", reversal_response.message
  end

  def test34
    credit_card = CreditCard.new(
      brand: "discover",
      month: "03",
      number: "6011010000000003",
      verification_value: "758",
      year: "2021"
    )

    options = {
        billing_address: {
          address1: "3 Main St.",
          city: "Bloomfield",
          country: "US",
          name: "Eileen Jones",
          state: "CT",
          zip: "06002"
        },
        order_id: "34"
    }

    # 34: Authorization
    auth_response = @gateway.authorize(30030, credit_card, options)

    assert_equal "000", auth_response.params["response"]
    assert_equal "Approved", auth_response.message
    assert_equal "33333", auth_response.params["authCode"].strip
    assert_equal "Z", auth_response.avs_result["code"]
    assert_equal "M", auth_response.cvv_result["code"]

    # 34A: Authorization Reversal
    reversal_response = @gateway.void(auth_response.authorization)

    assert_equal "000", reversal_response.params["response"]
    assert_equal "Approved", reversal_response.message
  end

  def test35
    credit_card = CreditCard.new(
      brand: "american_express",
      month: "04",
      name: "Bob Black",
      number: "375001000000005",
      year: "2021"
    )

    options = {
      billing_address: {
        address1: "4 Main St.",
        city: "Laurel",
        country: "US",
        state: "MD",
        zip: "20708"
      },
      order_id: "35"
    }

    # 35: Authorization
    auth_response = @gateway.authorize(10100, credit_card, options)

    assert_equal "000", auth_response.params["response"]
    assert_equal "Approved", auth_response.message
    assert_equal "44444", auth_response.params["authCode"].strip
    assert_equal "A", auth_response.avs_result["code"]

    # 35A: Capture
    capture_response = @gateway.capture(5050, auth_response.authorization)

    assert_equal "000", capture_response.params["response"]
    assert_equal "Approved", capture_response.message

    # 35B fails intermittently if capture does not have enough time to process
    sleep(TXN_PROCESSING_TIME)

    # 35B: Authorization Reversal
    reversal_options = {
      amount: 5050
    }

    reversal_response = @gateway.void(auth_response.authorization, reversal_options)

    assert_equal "336", reversal_response.params["response"]
    assert_equal "Reversal amount does not match authorization amount", reversal_response.message
  end

  def test36
    credit_card = CreditCard.new(
      brand: "american_express",
      month: "05",
      number: "375000026600004",
      year: "2021"
    )

    options = {
      order_id: "36"
    }

    # 36: Authorization
    auth_response = @gateway.authorize(20500, credit_card, options)

    assert_equal "000", auth_response.params["response"]
    assert_equal "Approved", auth_response.message

    # 36A: Authorization Reversal
    reversal_response = @gateway.void(auth_response.authorization, amount: 10000)

    assert_equal "336", reversal_response.params["response"]
    assert_equal "Reversal amount does not match authorization amount", auth_response.message
  end

  ### Order Ids 37 through 40 - eCheck Verification certification tests
  ## Not Implemented - Required if you plan to use eCheck Verification

  ### eCheck Prenotification certification tests
  ## Not Implemented - Required if you plan to use eCheck Prenotification

  ### Order Ids 41 through 44 - eCheck Sale certification tests
  def test41
    check = Check.new(
      account_holder_type: "personal",
      account_number: "10@BC99999",
      account_type: "checking",
      routing_number: "053100300"
    )

    options = {
      billing_address: {
        first_name: "Mike",
        last_name: "Hammer",
        middle_initial: "J"
      },
      order_id: "41",
      order_source: "telephone"
    }

    response = @gateway.purchase(2008, check, options)
    assert_equal "301", response.params["response"]
    assert_equal "Invalid Account Number", response.params["message"]
  end

  def test42
    check = Check.new(
      account_holder_type: "personal",
      account_number: "4099999992",
      account_type: "checking",
      routing_number: "011075150"
    )

    options = {
      billing_address: {
        first_name: "Tom",
        last_name: "Black"
      },
      order_id: "42",
      order_source: "telephone"
    }

    response = @gateway.purchase(2004, check, options)

    assert_equal "000", response.params["response"]
    assert_equal "Approved", response.params["message"]

    # eCheck Void transaction test
    options[:order_id] = "42_void"

    sale_response = @gateway.purchase(2004, check, options)
    void_response = @gateway.void(sale_response.authorization, options)

    assert_equal "000", void_response.params["response"]
    assert_equal "Approved", void_response.params["message"]
  end

  # The documentation says that Test 48 should use the ID returned from Test 43
  def test43_and_48
    check = Check.new(
      account_holder_type: "business",
      account_number: "6099999992",
      account_type: "checking",
      routing_number: "011075150"
    )

    options = {
      billing_address: {
        company_name: "Green Co",
        first_name: "Peter",
        last_name: "Green"
      },
      order_id: "43",
      order_source: "telephone"
    }

    response = @gateway.purchase(2007, check, options)
    assert_equal "000", response.params["response"]
    assert_equal "Approved", response.params["message"]

    options = {
      order_id: "48"
    }

    response = @gateway.refund(nil, response.authorization, options)
    assert_equal "000", response.params["response"]
    assert_equal "Approved", response.params["message"]
  end

  def test44
    check = Check.new(
      account_holder_type: "business",
      account_number: "9099999992",
      account_type: "checking",
      routing_number: "053133052"
    )

    options = {
      billing_address: {
        company_name: "Green Co",
        first_name: "Peter",
        last_name: "Green"
      },
      order_id: "44",
      order_source: "telephone"
    }

    response = @gateway.purchase(2009, check, options)
    assert_equal "900", response.params["response"]
    assert_equal "Invalid Bank Routing Number", response.params["message"]
  end

  ### Order Ids 45 through 49 - eCheck Credit certification tests
  def test45
    check = Check.new(
      account_holder_type: "personal",
      account_number: "10@BC99999",
      account_type: "checking",
      routing_number: "053100300"
    )

    options = {
      billing_address: {
        first_name: "John",
        last_name: "Smith"
      },
      order_id: "45",
      order_source: "telephone"
    }

    response = @gateway.refund(1001, check, options)
    assert_equal "301", response.params["response"]
    assert_equal "Invalid Account Number", response.params["message"]
  end

  def test46
    check = Check.new(
      account_holder_type: "business",
      account_number: "3099999999",
      account_type: "checking",
      routing_number: "011075150"
    )

    options = {
      billing_address: {
        companyName: "Widget Inc",
        first_name: "Robert",
        last_name: "Jones"
      },
      order_id: "46",
      order_source: "telephone"
    }

    credit_response = @gateway.refund(1003, check, options)

    assert_equal "000", credit_response.params["response"]
    assert_equal "Approved", credit_response.params["message"]

    # eCheck Void transaction test
    options[:order_id] = "46_void"

    credit_response = @gateway.refund(1003, check, options)
    void_response = @gateway.void(credit_response.authorization, options)

    assert_equal "000", void_response.params["response"]
    assert_equal "Approved", void_response.params["message"]
  end

  def test47
    check = Check.new(
      account_holder_type: "business",
      account_number: "6099999993",
      account_type: "checking",
      routing_number: "211370545"
    )

    options = {
      billing_address: {
        company_name: "Green Co",
        first_name: "Peter",
        last_name: "Green"
      },
      order_id: "47",
      order_source: "telephone"
    }

    response = @gateway.refund(1007, check, options)
    assert_equal "000", response.params["response"]
    assert_equal "Approved", response.params["message"]
  end

  def test49
    options = {
      order_id: "49"
    }

    authorization = VantivGateway::Authorization.new(
      litle_txn_id: "2",
      txn_type: :echeckSales
    )

    credit_response = @gateway.refund(nil, authorization, options)

    assert_equal "360", credit_response.params["response"]
    assert_equal "No transaction found with specified litleTxnId", credit_response.params["message"]

    # eCheck Void transaction test
    void_response = @gateway.void(authorization)

    assert_equal "360", void_response.params["response"]
    assert_equal "No transaction found with specified litleTxnId", void_response.params["message"]
  end

  ### Order Ids 50 through 52 - Explicit card tokenization certification tests
  def test50
    credit_card = CreditCard.new(number: "4457119922390123")

    options = {
      order_id: "50"
    }

    # registerTokenRequest
    store_response = @gateway.store(credit_card, options)

    assert_equal "0123", store_response.params["litleToken"][-4,4]
    assert_equal "445711", store_response.params["bin"]
    assert_equal "VI", store_response.params["type"]

    # Note: These assertions do not pass after the first time this test is run
    assert_equal "801", store_response.params["response"]
    assert_equal "Account number was successfully registered", store_response.message
  end

  def test51
    credit_card = CreditCard.new(number: "4457119999999999")

    options = {
      order_id: "51"
    }

    # registerTokenRequest
    store_response = @gateway.store(credit_card, options)

    assert_equal nil, store_response.params["tokenResponse_litleToken"]
    assert_equal "820", store_response.params["response"]
    assert_equal "Credit card number was invalid", store_response.message
  end

  def test52
    credit_card = CreditCard.new(number: "4457119922390123")

    options = {
      order_id: "52"
    }

    # registerTokenRequest
    store_response = @gateway.store(credit_card, options)

    assert_equal "0123", store_response.params["litleToken"][-4,4]
    assert_equal "445711", store_response.params["bin"]
    assert_equal "VI", store_response.params["type"]
    assert_equal "802", store_response.params["response"]
    assert_equal "Account number was previously registered", store_response.message
  end

  ### Order Ids 53 through 54 - Explicit eCheck tokenization certification tests
  ## Not Implemented - Required for eCheck token users

  ### Order Ids 55 through 57 - Implicit card tokenization certification tests
  def test55
    credit_card = CreditCard.new(
      brand: "master",
      month: "11",
      number: "5435101234510196",
      verification_value: "987",
      year: "2021"
    )

    options = {
        order_id: "55"
    }

    # Token is implicitly registered during authorization request
    response = @gateway.authorize(15000, credit_card, options)

    assert_equal "000", response.params["response"]
    assert_equal "Approved", response.message
    assert_equal "0196", response.params["tokenResponse_litleToken"][-4,4]
    assert_equal "MC", response.params["tokenResponse_type"]
    assert_equal "543510", response.params["tokenResponse_bin"]
    # Note: These assertions do not pass after the first time this test is run
    assert_equal "801", response.params["tokenResponse_tokenResponseCode"]
    assert_equal "Account number was successfully registered", response.message
  end

  def test56
    credit_card = CreditCard.new(
      brand: "master",
      month: "11",
      number: "5435109999999999",
      verification_value: "987",
      year: "2021"
    )

    options = {
      order_id: "56"
    }

    # Token is implicitly registered during authorization request
    assert response = @gateway.authorize(15000, credit_card, options)

    assert_equal "301", response.params["response"]
    assert_equal "Invalid Account Number", response.message
  end

  ### Order Ids 58 through 60 - Authorization with token certification tests
  # The documentation says that Test 58 should use the token from Test 57
  def test57_and_58
    credit_card = CreditCard.new(
      brand: "master",
      month: "11",
      number: "5435101234510196",
      verification_value: "987",
      year: "2021"
    )

    options = {
      order_id: "57"
    }

    # Token is implicitly registered during authorization request
    response = @gateway.authorize(15000, credit_card, options)

    assert_equal "000", response.params["response"]
    assert_equal "0196", response.params["tokenResponse_litleToken"][-4,4]
    assert_equal "Approved", response.message
    assert_equal "802", response.params["tokenResponse_tokenResponseCode"]
    assert_equal "Account number was previously registered", response.params["tokenResponse_tokenMessage"]
    assert_equal "MC", response.params["tokenResponse_type"]
    assert_equal "543510", response.params["tokenResponse_bin"]

    token = VantivGateway::Token.new(
      response.params["tokenResponse_litleToken"],
      month: credit_card.month,
      verification_value: credit_card.verification_value,
      year: credit_card.year
    )

    options = {
      order_id: "58"
    }

    # Authorize with the implicity registered token from test 57
    response = @gateway.authorize(15000, token, options)

    assert_equal "000", response.params["response"]
    assert_equal "Approved", response.message
  end

  def test59
    token = ActiveMerchant::Billing::VantivGateway::Token.new(
      "1111000100092332",
      month: "11",
      year: "2021"
    )

    options = {
      order_id: "59",
    }

    response = @gateway.authorize(15000, token, options)

    assert_equal "822", response.params["response"]
    assert_equal "Token was not found", response.message
  end

  def test60
    token = ActiveMerchant::Billing::VantivGateway::Token.new(
      "1112000100000085",
      month: "11",
      year: "2021"
    )

    options = {
      order_id: "60"
    }

    response = @gateway.authorize(15000, token, options)

    assert_equal "823", response.params["response"]
    assert_equal "Token was invalid", response.message
  end

  ### Order Ids 61 through 64 - Implicit eCheck tokenization certification tests
  ## Not Implemented - Required for eCheck token users

  ### Order Ids after 64 are optional tests after completing certification
  ## Functionality covered in those tests may or may not be implemented

  private

  def auth_assertions(amount, card, options, assertions)
    # 1: authorize
    assert response = @gateway.authorize(amount, card, options)
    assert_success response
    assert_equal "000", response.params["response"]
    assert_equal 'Approved', response.message
    assert_equal assertions[:avs], response.avs_result["code"]
    assert_equal assertions[:cvv], response.cvv_result["code"] if assertions[:cvv]
    assert_equal assertions[:auth_code], response.params["authCode"].strip if assertions[:auth_code]
    assert_equal options[:order_id], response.params['orderId']

    # 1A: capture
    id = transaction_id
    assert response = @gateway.capture(amount, response.authorization, {:id => id})
    assert_equal 'Approved', response.message

    # 1B: credit
    id = transaction_id
    assert response = @gateway.refund(amount, response.authorization, {:id => id})
    assert_equal 'Approved', response.message

    # 1C: void
    id = transaction_id
    assert response = @gateway.void(response.authorization, {:id => id})
    assert_equal 'Approved', response.message
  end

  def authorize_avs_assertions(credit_card, options, assertions={})
    assert response = @gateway.authorize(0, credit_card, options)
    assert_equal assertions.key?(:success) ? assertions[:success] : true, response.success?
    assert_equal assertions[:message] || 'Approved', response.message
    assert_equal assertions[:avs], response.avs_result["code"], caller.inspect
    assert_equal assertions[:cvv], response.cvv_result["code"], caller.inspect if assertions[:cvv]
    assert_equal options[:order_id], response.params['orderId']
  end

  def sale_assertions(amount, card, options, assertions)
    # 1: sale
    assert response = @gateway.purchase(amount, card, options)
    assert_success response
    assert_equal 'Approved', response.message
    assert_equal assertions[:avs], response.avs_result["code"]
    assert_equal assertions[:cvv], response.cvv_result["code"] if assertions[:cvv]
    assert_equal options[:order_id], response.params['orderId']

    # 1B: credit
    id = transaction_id
    assert response = @gateway.refund(amount, response.authorization, {:id => id})
    assert_equal 'Approved', response.message

    # 1C: void
    id = transaction_id
    assert response = @gateway.void(response.authorization, {:id => id})
    assert_equal 'Approved', response.message
  end

  def transaction_id
    # A unique identifier assigned by the presenter and mirrored back in the response.
    # This attribute is also used for Duplicate Transaction Detection.
    # For Online transactions, omitting this attribute, or setting it to a
    # null value (id=""), disables Duplicate Detection for the transaction.
    #
    # minLength = N/A   maxLength = 25
    generate_unique_id[0, 24]
  end
end
