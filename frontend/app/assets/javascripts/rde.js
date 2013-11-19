//= require jquery.event.drag-1.4.min
//= require jquery.kiketable.colsizable-1.1
//= require jquery.columnmanager.min
//= require bootstrap-multiselect
//= require jquery.dragtable

$(function() {

  $.fn.init_rapid_data_entry_form = function($modal, $node) {
    $(this).each(function() {
      var $this = $(this);
      var $table = $("table#rdeTable", $this);

      if ($this.hasClass("initialised")) {
        return;
      }

      // Config from Cookies
      var VISIBLE_COLUMN_IDS =  $.cookie("rde.visible") ? JSON.parse($.cookie("rde.visible")) : null;
      var STICKY_COLUMN_IDS =  $.cookie("rde.sticky") ? JSON.parse($.cookie("rde.sticky")) : null;
      var COLUMN_WIDTHS =  $.cookie("rde.widths") ? JSON.parse($.cookie("rde.widths")) : null;
      var COLUMN_ORDER =  $.cookie("rde.order") ? JSON.parse($.cookie("rde.order")) : null;


      var index = 0;

      $modal.off("click").on("click", ".remove-row", function(event) {
        event.preventDefault();
        event.stopPropagation();

        var $btn = $(event.target).closest("button");

        if ($btn.hasClass("btn-danger")) {
          $btn.closest("tr").remove();
        } else {
          $btn.addClass("btn-danger");
          $("span", $btn).addClass("icon-white");
          setTimeout(function() {
            $btn.removeClass("btn-danger");
            $("span", $btn).removeClass("icon-white");
          }, 10000);
        }
      });

      $modal.on("click", "#rde_reset", function(event) {
        event.preventDefault();
        event.stopPropagation();

        $(":input, .btn", $this).attr("disabled", "disabled");

        // reset cookies
        $.cookie("rde.visible", null);
        $.cookie("rde.widths", null);
        $.cookie("rde.sticky", null);
        $.cookie("rde.order", null);
        VISIBLE_COLUMN_IDS = null;
        STICKY_COLUMN_IDS = null;
        COLUMN_WIDTHS = null;
        COLUMN_ORDER = null;

        // reload the form
        $(document).triggerHandler("rdeload.aspace", [$node, $modal]);
      });

      $modal.on("click", ".add-row", function(event) {
        event.preventDefault();
        event.stopPropagation();

        var $row = addRow();

        $(":input:visible:first", $row).focus();
      });

      var addRow = function() {
        var $currentRow = $(event.target).closest("tr");
        if ($currentRow.length === 0) {
          $currentRow = $("table tbody tr:last", $this);
        }

        index = index+1;

        var $row = $(AS.renderTemplate("template_rde_row", {
          path: "archival_record_children[children]["+index+"]",
          id_path: "archival_record_children_children__"+index+"_",
          index: index
        }));

        $(".fieldset-labels th", $this).each(function(i, th) {
          var $th = $(th);

          // Apply any sticky columns
          if ($currentRow.length > 0) {
            if ($th.hasClass("fieldset-label") && $th.hasClass("sticky")) {
              // populate the input from the current or bottom row
              var $source = $(":input:first", $("td", $currentRow).get(i));
              var $target = $(":input:first", $("td", $row).get(i));

              if ($source.is(":checkbox")) {
                if ($source.attr("checked")) {
                  $target.attr("checked", "checked");
                } else {
                  $target.removeAttr("checked");
                }
              } else {
                $target.val($source.val());
              }
            }
          }

          // Apply hidden columns
          if ($th.hasClass("fieldset-label") && !isVisible($th.attr("id"))) {
            $($("td", $row).get(i)).hide();
          }
        });

        $currentRow.after($row);
        return $row;
      };

      $modal.off("keydown").on("keydown", function(event) {
        if (event.keyCode === 27) { //esc
          event.preventDefault();
          event.stopImmediatePropagation();
        }
      });

      $modal.on("keydown", ":input, input[type='text']", function(event) {
        var $row = $(event.target).closest("tr");
        var $cell = $(event.target).closest("td");

        if (event.keyCode === 13) { // return
          event.preventDefault();

          if (event.shiftKey) {
              $(".add-row", $row).trigger("click");
              $(":input:visible:first", $("td", $row.next())[$cell.index()]).focus();
          }
        } else if (event.keyCode === 27) { //esc
          event.preventDefault();
          event.stopImmediatePropagation();
          return true;
        } else if (event.keyCode === 37) { // left
          if (event.shiftKey) {
            event.preventDefault();
            $(":input:visible:first", $cell.prev()).focus();
          }
        } else if (event.keyCode === 40) { // down
          if (event.shiftKey) {
            event.preventDefault();
            if ($row.index() < $row.siblings().length) {
              $(":input:visible:first", $("td", $row.next())[$cell.index()]).focus();
            }
          }
        } else if (event.keyCode === 38) { // up
          if (event.shiftKey) {
            event.preventDefault();
            if ($row.index() > 0) {
              $(":input:visible:first", $("td", $row.prev())[$cell.index()]).focus();
            }
          }
        } else if (event.keyCode === 39) { // right
          if (event.shiftKey) {
            event.preventDefault();
            $(":input:visible:first", $cell.next()).focus();
          }
        } else {
          // we're cool.
        }
      });

      /*$modal.on("click", "th.fieldset-label", function(event) {
        $(this).toggleClass("sticky");
        var sticky = [];
        $("table th.sticky", $this).each(function() {
          sticky.push($(this).attr("id"));
        });
        STICKY_COLUMN_IDS = sticky;
        $.cookie("rde.sticky", JSON.stringify(STICKY_COLUMN_IDS));
      });*/

      $modal.on("click", "[data-dismiss]", function(event) {
        $modal.modal("hide");
      });

      var initAjaxForm = function() {
        $this.ajaxForm({
          target: $(".rde-wrapper", $modal),
          success: function() {
            $(window).trigger("resize");
            $this = $("form", "#rapidDataEntryModal");
            $table = $("table", $this);

            if ($this.length) {
              $("tbody tr", $this).each(function() {
                var $row = $(this);
                if ($("td.error", $row).length > 0) {
                  $row.addClass("invalid");
                } else {
                  $row.addClass("valid");
                }
              });

              $("#form_messages .error[data-target]", $this).each(function() {
                // tweak the error message to match the column heading
                var $input = $("#"+$(this).data("target"));
                var $cell = $input.closest("td");
                var $row = $cell.closest("tr");
                var headerText = $($(".fieldset-labels th", $table).get($cell.index())).text();
                var newMessageText = $this.data("error-prefix") + " " + ($row.index()+1) + ": " + headerText + " - " + $(this).data("message");

                $(this).html(newMessageText);
                if ($(this).hasClass("linked-to-field")) {
                  $(this).append("<span class='icon-chevron-down'></span>");
                }
              });

              initAjaxForm();
            } else {
              // we're good to go!
              setTimeout(function() {
                location.reload(true);
              }, 1000);
            }
          }
        });

        // add ability to resize columns
        $table.kiketable_colsizable({
          dragCells: "tr.fieldset-labels th.fieldset-label",
          dragMove: true
        });
        $("th.fieldset-label .kiketable-colsizable-handler", $table).on("dragend", persistColumnWidths);

        // add show/hide
        $table.columnManager();

        // give the columns an id
        $("table thead .fieldset-labels th").each(function(i, col) {
          if (!$(col).attr("id")) {
            $(col).attr("id", "rdecol"+i);
          }
          $($("table colgroup col").get(i)).data("id", $(col).attr("id"));
        });

        applyColumnOrder();
        initColumnReorderFeature();
        applyPersistentStickyColumns();
        initColumnShowHideWidget();
        initFillFeature();
      };

      var initFillFeature = function() {
        var $fillFormsContainer = $(".fill-column-form", $modal);
        var $btnFillFormToggle = $("button.fill-column", $modal);

        var $sourceRow = $("table tbody tr:first", $this);

        // Setup global events
        $("button.fill-column", $modal).click(function(event) {
          event.preventDefault();
          event.stopPropagation();

          $btnFillFormToggle.toggleClass("active");
          $fillFormsContainer.slideToggle();
        });

        // Setup Basic Fill form
        var setupBasicFillForm = function() {
          var $form = $("#fill_basic", $fillFormsContainer);
          var $inputTargetColumn = $("#basicFillTargetColumn", $form);
          var $btnFill = $("button", $form);

          // populate the column selectors
          populateColumnSelector($inputTargetColumn);

          $inputTargetColumn.change(function() {
            $(".empty", this).remove();

            var colIndex = parseInt($("#"+$(this).val()).index());

            var $input = $(":input:first", $("td", $sourceRow).get(colIndex)).clone();
            $input.attr("name", "").attr("id", "basicFillValue");
            $(".fill-value-container", $form).html($input);
            $btnFill.removeAttr("disabled").removeClass("disabled");
          });

          $btnFill.click(function(event) {
            event.preventDefault();
            event.stopPropagation();

            var colIndex = parseInt($("#"+$inputTargetColumn.val()).index())+1;

            var $targetCells = $("table tbody tr td:nth-child("+colIndex+")", $this);

            if ($("#basicFillValue",$form).is(":checkbox")) {
              var fillValue = $("#basicFillValue",$form).is(":checked");
              if (fillValue) {
                $(":input:first", $targetCells).attr("checked", "checked");
              } else {
                $(":input:first", $targetCells).removeAttr("checked");
              }
            } else {
              var fillValue = $("#basicFillValue",$form).val();
              $(":input:first", $targetCells).val(fillValue);
            }

            $btnFillFormToggle.toggleClass("active");
            $fillFormsContainer.slideToggle();
          });
        };

        // Setup Sequence Fill form
        var setupSequenceFillForm = function() {
          var $form = $("#fill_sequence", $fillFormsContainer);
          var $inputTargetColumn = $("#sequenceFillTargetColumn", $form);
          var $btnFill = $("button.btn-primary", $form);
          var $sequencePreview = $(".sequence-preview", $form);

          // populate the column selectors
          populateColumnSelector($inputTargetColumn, null, function($colHeader) {
            var $td = $("td", $sourceRow).get($colHeader.index());
            return $(":input:first", $td).is(":text");
          });

          $inputTargetColumn.change(function() {
            $(".empty", this).remove();
            $btnFill.removeAttr("disabled").removeClass("disabled");
          });

          $("button.preview-sequence", $form).click(function(event) {
            event.preventDefault();
            event.stopPropagation();

            $.getJSON($form.data("sequence-generator-url"),
                      {
                        prefix: $("#sequenceFillPrefix", $form).val(),
                        from: $("#sequenceFillFrom", $form).val(),
                        to: $("#sequenceFillTo", $form).val(),
                        suffix: $("#sequenceFillSuffix", $form).val()
                      },
                      function(json) {
                        $sequencePreview.html("");
                        if (json.errors) {
                          $.each(json.errors, function(i, error) {
                            var $error = $("<div>").html(error).addClass("text-error");
                            $sequencePreview.append($error);
                          });
                        } else {
                          $sequencePreview.html($("<p class='values'>").html(json.values.join(", ")));
                          $sequencePreview.prepend($("<p class='summary'>").html(json.summary));
                        }
                      }
            );
          });

          var applySequenceFill = function(force) {
            $("#sequenceTooSmallMsg", $form).hide();

            $.getJSON($form.data("sequence-generator-url"),
                {
                  prefix: $("#sequenceFillPrefix", $form).val(),
                  from: $("#sequenceFillFrom", $form).val(),
                  to: $("#sequenceFillTo", $form).val(),
                  suffix: $("#sequenceFillSuffix", $form).val()
                },
                function(json) {
                  $sequencePreview.html("");
                  if (json.errors) {
                    $.each(json.errors, function(i, error) {
                      var $error = $("<div>").html(error).addClass("text-error");
                      $sequencePreview.append($error);
                    });
                    return;
                  }

                  // check if less items in sequence than rows
                  if (!force && json.values.length < $("tbody tr", $modal).length) {
                    $("#sequenceTooSmallMsg", $form).show();
                    return;
                  }

                  // Good to go. Apply values.
                  var $targetCells = $("table tbody tr td:nth-child("+(parseInt($inputTargetColumn.val())+1)+")", $this);
                  $.each(json.values, function(i, val) {
                    if (i > $targetCells.length) {
                      return;
                    }
                    $(":input:first", $targetCells[i]).val(val);
                  });

                  $btnFillFormToggle.toggleClass("active");
                  $fillFormsContainer.slideToggle();
                }
            );
          }

          $btnFill.click(function(event) {
            event.preventDefault();
            event.stopPropagation();

            applySequenceFill(false);
          });

          $(".btn-continue-sequence-fill", $form).click(function(event) {
            event.preventDefault();
            event.stopPropagation();

            applySequenceFill(true);
          });
        };

        setupBasicFillForm();
        setupSequenceFillForm();
      };

      var persistColumnOrder = function() {
        var column_ids = [];
        $("table .fieldset-labels th", $this).each(function() {
          column_ids.push($(this).attr("id"));
        });
        COLUMN_ORDER = column_ids;
        $.cookie("rde.order", JSON.stringify(COLUMN_ORDER));
      };

      var applyColumnOrder = function() {
        if (COLUMN_ORDER === null) {
          persistColumnOrder();
        } else {
          // apply order from cookie
          var $row = $("tr.fieldset-labels", $table);
          var $colgroup = $("colgroup", $table);

          $.each(COLUMN_ORDER, function(targetIndex, colId) {
            var $th = $("#" + colId, $row);
            var currentIndex = $th.index();
            var $col = $($("col", $colgroup).get(currentIndex));

            if (targetIndex !== currentIndex) {
                $th.insertBefore($("th", $row).get(targetIndex));
                $col.insertBefore($("col", $colgroup).get(targetIndex));
                $("tbody tr", $table).each(function(i, $tr) {
                  $($("td", $tr).get(currentIndex)).insertBefore($("td", $tr).get(targetIndex));
                });
            }
          });
        }
      };

      var initColumnReorderFeature = function() {
        var $reorderContainer = $("#columnReorderForm", $modal);
        var $btnReorderToggle = $("button.reorder-columns", $modal);
        var $select = $("#columnOrder", $reorderContainer);
        var $btnApplyOrder = $(".btn-primary", $reorderContainer);


        // Setup global events
        $btnReorderToggle.click(function(event) {
          event.preventDefault();
          event.stopPropagation();

          $btnReorderToggle.toggleClass("active");
          $reorderContainer.slideToggle();
        });

        populateColumnSelector($select);
        $select.attr("size", $("option", $select).length / 2);

        var handleMove = function(direction) {
          var $options = $("option:selected", $select);
          if ($options.length) {
            if (direction === "up") {
              $options.first().prev().before($options);
            } else {
              $options.last().next().after($options);
            }
          }
          $btnApplyOrder.removeAttr("disabled").removeClass("disabled");
        };

        var resetForm = function() {
          $btnReorderToggle.toggleClass("active");
          $reorderContainer.slideToggle(function() {
            $btnApplyOrder.addClass("disabled").attr("disabled", "disabled");
            // reset the select
            $select.html("");
            populateColumnSelector($select);
          });
        }

        $('#columnOrderUp', $reorderContainer).bind('click', function() {
          handleMove("up");
        });
        $('#columnOrderDown', $reorderContainer).bind('click', function() {
          handleMove("down");
        });
        $(".btn-cancel", $reorderContainer).click(function(event) {
          event.preventDefault();
          event.stopPropagation();

          resetForm();
        });
        $btnApplyOrder.click(function(event) {
          event.preventDefault();
          event.stopPropagation();

          COLUMN_ORDER = ["colStatus"];
          $("option", $select).each(function() {
            COLUMN_ORDER.push($(this).val());
          });
          COLUMN_ORDER.push("colActions");

          applyColumnOrder();
          resetForm();
          persistColumnOrder();
        });
      };

      var populateColumnSelector = function($select, select_func, filter_func) {
        filter_func = filter_func || function() {return true;};
        select_func = select_func || function() {return false;};
        $(".fieldset-labels th", $this).each(function() {
          var $colHeader = $(this);
          if ($colHeader.hasClass("fieldset-label") && filter_func($colHeader)) {
            var $option = $("<option>");
            $option.val($colHeader.attr("id")).text($colHeader.text());
            if (select_func($colHeader)) {
              $option.attr("selected", "selected");
            }
            $select.append($option);
          }
        });
      };

      var initColumnShowHideWidget = function() {
        var $select = $("#rde_hidden_columns");
        populateColumnSelector($select, function($colHeader) {
          return isVisible($colHeader.attr("id"));
        });
        $select.multiselect({
          buttonClass: 'btn btn-small',
          buttonWidth: 'auto',
          maxHeight: 300,
          buttonContainer: '<div class="btn-group" />',
          buttonText: function(options) {
            if (options.length == 0) {
              return $select.data("i18n-none") + ' <b class="caret"></b>';
            }
            else if (options.length > 5) {
              return $select.data("i18n-prefix") + ' ' + options.length + ' ' + $select.data("i18n-suffix") + ' <b class="caret"></b>';
            }
            else {
              var selected = $select.data("i18n-prefix") + " ";
              options.each(function() {
                selected += $(this).text() + ', ';
              });
              return selected.substr(0, selected.length -2) + ' <b class="caret"></b>';
            }
          },
          onChange: function($option, checked) {
            var widths = persistColumnWidths();
            var colId = $option.val();
            var index = $("#" + colId).index();

            if (checked) {
              $table.showColumns(index+1);
              var $col = $($("table colgroup col").get(index));
              $col.show();
              $table.width($table.width() + widths[index]);
            } else {
              hideColumn(index);
            }

            VISIBLE_COLUMN_IDS = $select.val();
            $.cookie("rde.visible", JSON.stringify(VISIBLE_COLUMN_IDS));
          }
        });

        applyPersistentVisibleColumns();
      };

      var persistColumnWidths = function() {
        var widths = {};
        $("table colgroup col", $this).each(function(i, col) {
          if ($(col).width() === 0) {
            $(col).width($(col).data("default-width"));
          }
          widths[$(col).data("id")] = $(col).width();
        });

        COLUMN_WIDTHS = widths;
        $.cookie("rde.widths", JSON.stringify(COLUMN_WIDTHS));

        return COLUMN_WIDTHS;
      };

      var setColumnWidth = function(colId) {
        var width = getColumnWidth(colId);
        var index = $("#"+colId).index();

        // set width of corresponding col element
        $($("table colgroup col", $this).get(index)).width(width);

        return width;
      };

      var getColumnWidth = function(colId) {
        if ( COLUMN_WIDTHS ) {
          return COLUMN_WIDTHS[colId];
        } else {
          persistColumnWidths();
          return getColumnWidth(colId);
        }
      };

      var applyPersistentColumnWidths = function() {
        var total_width = 0;

        $("table colgroup col", $this).each(function(i, el) {
          var colW = getColumnWidth($(el).data("id"));
          $(el).width(colW);
          total_width += colW;
        });

        $table.width(total_width);
      };

      var applyPersistentStickyColumns = function() {
        if ( STICKY_COLUMN_IDS ) {
          $("th.sticky", $this).removeClass("sticky");
          $.each(STICKY_COLUMN_IDS, function() {
            $("#" + this).addClass("sticky");
          });
        }
      };

      var isVisible = function(colId) {
        if ( VISIBLE_COLUMN_IDS ) {
          return  $.inArray(colId, VISIBLE_COLUMN_IDS) >= 0
        } else {
          return true;
        }
      };

      var applyPersistentVisibleColumns = function() {
        if ( VISIBLE_COLUMN_IDS ) {
          var total_width = 0;

          $.each($(".fieldset-labels th", $this), function() {
            var colId = $(this).attr("id");
            var index = $(this).index();

            if ($(this).hasClass("fieldset-label")) {
              if (isVisible(colId)) {
                total_width += setColumnWidth(colId);
              } else {
                hideColumn(index);
              }
            } else {
              total_width += setColumnWidth(colId);
            }
          });
          $table.width(total_width);
        } else {
          applyPersistentColumnWidths();
        }
      };

      var hideColumn = function(index) {
        $("#rde_hidden_columns").multiselect('deselect', index+"");
        $table.hideColumns(index+1);
        var $col = $($("table colgroup col").get(index));
        $table.width($table.width() - $col.width());
        $col.hide();
      };

      // Connect up the $modal form submit button
      $($modal).on("click", ".modal-footer .btn-primary", function() {
        $(this).attr("disabled","disabled");
        $this.submit();
      });

      // enable form within the add row dropdown menu
      $(".add-rows-form input", $modal).click(function(event) {
        event.preventDefault();
        event.stopPropagation();
      });
      $(".add-rows-form button", $modal).click(function() {
        try {
          var numberOfRows = parseInt($("input", $(this).closest('.add-rows-form')).val(), 10);
          for (var i=1; i<=numberOfRows; i++) {
            addRow();
          }
        } catch(e) {
          // if the field cannot parse the form value to an integer.. just quietly judge the user
        }
      });

      initAjaxForm();

      $(window).trigger("resize");
      $(document).triggerHandler("loadedrecordform.aspace", [$this]);
    });
  };

  $(document).bind("rdeload.aspace", function(event, $node, $modal) {
    $.ajax({
      url: "/"+$node.attr("rel")+"s/"+$node.data("id")+"/rde",
      success: function(data) {
        $(".rde-wrapper", $modal).replaceWith("<div class='modal-body'></div>");
        $(".modal-body", $modal).replaceWith(data);
        $("form", "#rapidDataEntryModal").init_rapid_data_entry_form($modal, $node);
      }
    });
  });

  $(document).bind("rdeshow.aspace", function(event, $node, $button) {
    var $modal = AS.openCustomModal("rapidDataEntryModal", $button.text(), AS.renderTemplate("modal_content_loading_template"), 'full', {keyboard: false});

    $(document).triggerHandler("rdeload.aspace", [$node, $modal]);
  });

});