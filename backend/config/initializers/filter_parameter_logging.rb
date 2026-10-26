# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc,
  # What a person types is not for the log (spec/requests/logging_spec.rb): the sentence given to the
  # planner (`text`, also matches the `original_text` column), the search terms, the domain they follow,
  # and the location. This also hides them in SQL values and in model `inspect`. The JSON columns that
  # copy those values (a plan, its analysis with quotes from the sentence, a run's request metadata) are
  # filtered by column name too, because filtering works on names, not on what is inside a value.
  :text, :query, :target_domain, :location, :plan, :analysis, :request_metadata
]
