// If JavaScript is enabled remove 'no-js' class and give 'js' class
jQuery('html').removeClass('no-js').addClass('js');

$(document).ready(function() {
    Stripe.setPublishableKey( $('meta[name="stripe-key"]').attr('content') );

    $("#payment_form").submit(function(event) {
        // disable the submit button to prevent repeated clicks
        $('#submit_button').attr("disabled", "disabled");

        Stripe.createToken({
            number: $('#card_number').val(),
            cvc: $('#card_cvc').val(),
            exp_month: $('#card_expiry_month').val(),
            exp_year: $('#card_expiry_year').val()
        }, stripeResponseHandler);

        // prevent the form from submitting with the default action
        return false;
    });

    stripeResponseHandler = function(status, response) {
        if (response.error) {
            // show the errors on the form
            $("#token_error").text(response.error.message);
            $("#token_error").show();
            $("#submit_button").removeAttr("disabled");
        } else {
            $("#token_error").hide();
            var form$ = $("#payment_form");
            // token contains id, last4, and card type
            var token = response['id'];
            // insert the token into the form so it gets submitted to the server
            form$.append("<input type='hidden' name='stripeToken' value='" + token + "'/>");
            // and submit
            form$.get(0).submit();
        }
    }
});