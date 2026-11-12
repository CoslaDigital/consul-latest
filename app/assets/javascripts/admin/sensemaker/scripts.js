(function() {
  "use strict";
  App.AdminSensemakerScripts = {

    initialize: function() {
      var buttons = ".admin .sensemaker form button[type='submit'][data-remote='true']";
      var inputs = ".admin .sensemaker form input[type='submit'][data-remote='true']";
      var remoteSubmits = $(buttons + ", " + inputs);

      remoteSubmits.on("click", function(event) {
        event.preventDefault();
        var form = $(this).closest("form");
        App.AdminSensemakerScripts.remoteSubmit(form, $(this));
      });

      var forms = $(".admin .sensemaker form");
      forms.on("submit", this.handleTempDisable);

      var busySelector =
        "button[type='submit'][data-temp-disable='true'], input[type='submit'][data-temp-disable='true']";
      forms.on("click", busySelector, this.applyBusyState);

      this.initializeStringLists(forms);
      this.initializeReportConfigDialogs(forms);
    },

    initializeReportConfigDialogs: function(forms) {
      forms.on("click", ".sensemaker-report-config-dialog button[name='quick_action']", function() {
        var activeDialog = $(this).closest(".sensemaker-report-config-dialog");
        $(".sensemaker-report-config-dialog").not(activeDialog).find(":input").prop("disabled", true);
        activeDialog.find(":input").prop("disabled", false);
      });
    },


    handleTempDisable: function() {
      App.AdminSensemakerScripts.applyBusyState.call(this, { currentTarget: this });
    },

    applyBusyState: function(event) {
      var form = $(event.currentTarget).closest("form");
      form.addClass("sensemaker-buttons-busy");
    },

    remoteSubmit: function(form, submitter) {
      var formData = form.serialize();
      var formAction = submitter.attr("formaction") || form.attr("action");
      var formMethod = form.attr("method") || "POST";

      $.ajax({
        url: formAction,
        type: formMethod,
        data: formData,
        dataType: "script" // This tells Rails to expect JavaScript response
      });
    },

    initializeStringLists: function(forms) {
      forms.on("click", "[data-sensemaker-string-list-add]", function(event) {
        event.preventDefault();
        var list = $(this).closest("[data-sensemaker-string-list]");
        var items = list.find("[data-sensemaker-string-list-items]");
        var row = items.find("[data-sensemaker-string-list-row]").first();
        if (!row.length) {
          return;
        }

        var clone = row.clone();
        clone.find("input").val("");
        items.append(clone);
      });

      forms.on("click", "[data-sensemaker-string-list-remove]", function(event) {
        event.preventDefault();
        var list = $(this).closest("[data-sensemaker-string-list]");
        var rows = list.find("[data-sensemaker-string-list-row]");
        var row = $(this).closest("[data-sensemaker-string-list-row]");

        if (rows.length > 1) {
          row.remove();
        } else {
          row.find("input").val("");
        }
      });
    }
  };
}).call(this);
