# frozen_string_literal: true

class User
  module MoneyBalance
    def unpaid_balance_cents(via: :sql)
      if via == :elasticsearch
        begin
          Balance.amount_cents_sum_for(self)
        rescue => e
          Bugsnag.notify(e)
          unpaid_balance_cents(via: :sql)
        end
      else
        balances.unpaid.sum(:amount_cents)
      end
    end

    def unpaid_balance_cents_up_to_date(date)
      balances.unpaid.where("date <= ?", date).sum(:amount_cents)
    end

    def unpaid_balance_cents_up_to_date_held_by_gumroad(date)
      balances.unpaid.where("date <= ?", date).where(merchant_account_id: gumroad_merchant_account_ids).sum(:amount_cents)
    end

    def unpaid_balance_holding_cents_up_to_date_held_by_stripe(date)
      creator_stripe_account = stripe_account
      return 0 unless creator_stripe_account.present?

      balances.unpaid.where("date <= ?", date).where(merchant_account_id: creator_stripe_account.id).sum(:holding_amount_cents)
    end

    def instantly_payable_unpaid_balance_cents
      instantly_payable_unpaid_balances.sum(&:holding_amount_cents)
    end

    def instantly_payable_unpaid_balance_cents_up_to_date(date)
      instantly_payable_unpaid_balances_up_to_date(date).sum(&:holding_amount_cents)
    end

    def instantly_payable_unpaid_balances
      instantly_payable_unpaid_balances_up_to_date(Date.today)
    end

    def instantly_payable_unpaid_balances_up_to_date(date)
      amount_cents_available_on_stripe = StripePayoutProcessor.instantly_payable_amount_cents_on_stripe(self)
      first_unpayable_balance_held_by_stripe_date = nil
      unpaid_balances_up_to_date(date).select { _1.merchant_account.holder_of_funds == HolderOfFunds::STRIPE }.sort_by(&:date).map(&:date).each do |date|
        balance_cents_held_by_stripe_till_date = unpaid_balances.where("date <= ?", date).select { _1.merchant_account.holder_of_funds == HolderOfFunds::STRIPE }.sum(&:holding_amount_cents)
        if (balance_cents_held_by_stripe_till_date * 100.0 / (100 + StripePayoutProcessor::INSTANT_PAYOUT_FEE_PERCENT)).floor > amount_cents_available_on_stripe
          first_unpayable_balance_held_by_stripe_date = date
          break
        end
      end
      payable_balances = unpaid_balances_up_to_date(date)
      payable_balances = payable_balances.where("date < ?", first_unpayable_balance_held_by_stripe_date) if first_unpayable_balance_held_by_stripe_date.present?
      payable_balances.select { _1.merchant_account.holder_of_funds.in?([HolderOfFunds::STRIPE, HolderOfFunds::GUMROAD]) }.sort_by(&:date)
    end

    def unpaid_balances_up_to_date(date)
      balances.unpaid.where("date <= ?", date)
    end

    def unpaid_balances
      balances.unpaid
    end

    def paid_payments_cents_for_date(date)
      payments.where(payout_period_end_date: date, state: %w[processing unclaimed completed]).sum(:amount_cents)
    end

    def formatted_balance_to_forfeit(reason)
      return if reason == :account_closure && Feature.inactive?(:delete_account_forfeit_balance, self)

      forfeiter = ForfeitBalanceService.new(user: self, reason:)

      forfeiter.balance_amount_formatted if forfeiter.balance_amount_cents_to_forfeit > 0
    end

    def forfeit_unpaid_balance!(reason)
      return if reason == :account_closure && Feature.inactive?(:delete_account_forfeit_balance, self)

      ForfeitBalanceService.new(user: self, reason:).process
    end

    def validate_account_closure_balances!
      forfeiter = ForfeitBalanceService.new(user: self, reason: :account_closure)

      if forfeiter.balance_amount_cents_to_forfeit != 0
        raise UnpaidBalanceError.new("Balance requires forfeiting", forfeiter.balance_amount_formatted)
      end
    end

    private
      def gumroad_merchant_account_ids
        @_gumroad_merchant_account_ids ||= [
          MerchantAccount.gumroad(StripeChargeProcessor.charge_processor_id),
          MerchantAccount.gumroad(BraintreeChargeProcessor.charge_processor_id)
        ]
      end
  end

  class UnpaidBalanceError < StandardError
    attr_reader :amount

    def initialize(message, amount)
      @amount = amount
      super(message)
    end
  end
end
