(function() {
  "use strict";
  App.Map = {
    maps: [],
    initialize: function() {
      $('*[data-map]:visible').each(function() {
        App.Map.initializeMap(this);
      });
    },
    destroy: function() {
      App.Map.maps.forEach(function(map) {
        map.off();
        map.remove();
      });
      App.Map.maps = [];
    },
    initializeMap: function(element) {
      var createMarker, editable, investmentsMarkers, map, marker, markerClustering,
        markerData, markerIcon, markers, moveOrPlaceMarker, removeMarker, removeMarkerSelector,
        geozoneLayers = {},
        layerControl = {};

      App.Map.cleanInvestmentCoordinates(element);
      removeMarkerSelector = $(element).data('marker-remove-selector');
      investmentsMarkers = $(element).data("marker-investments-coordinates");
      editable = $(element).data("marker-editable");
      markerClustering = $(element).data("marker-clustering");

      markers = markerClustering ? L.markerClusterGroup({ chunkedLoading: true }) : L.layerGroup();

      // ES5 Safe Marker Generation
      createMarker = function (latitude, longitude, color, icon) {
        var newMarker, markerLatLng, specificIcon;
        markerLatLng = new L.LatLng(latitude, longitude);

        var pinColor = color || "#00cae9";
        var pinIcon = icon || "map-marker-alt";

        // ES5 Safe String Concatenation (No Backticks)
        specificIcon = L.divIcon({
          className: "map-marker",
          iconSize: [30, 30],
          iconAnchor: [15, 40],
          html: '<div class="map-icon" style="--marker-color: ' + pinColor + ';">' +
            '<i class="fa fa-' + pinIcon + ' custom-pin-icon"></i>' +
            '</div>'
        });

        newMarker = L.marker(markerLatLng, {
          icon: specificIcon,
          draggable: editable
        });

        if (editable) {
          newMarker.on("dragend", function() {
            App.Map.updateFormfields(map, newMarker);
          });
        }
        markers.addLayer(newMarker);
        return newMarker;
      };

      removeMarker = function() {
        if (marker) {
          map.removeLayer(marker);
          marker = null;
        }
        App.Map.clearFormfields(element);
      };

      moveOrPlaceMarker = function(e) {
        if (marker) {
          marker.setLatLng(e.latlng);
        } else {
          marker = createMarker(e.latlng.lat, e.latlng.lng);
        }
        App.Map.updateFormfields(map, marker);
      };

      map = App.Map.leafletMap(element);
      App.Map.maps.push(map);
      App.Map.addAttribution(map);

      markerData = App.Map.markerData(element);
      if (markerData.lat && markerData.long && !investmentsMarkers) {
        marker = createMarker(markerData.lat, markerData.long);
      }

      if (editable) {
        $(removeMarkerSelector).on("click", removeMarker);
        map.on("zoomend", function() {
          if (marker) {
            App.Map.updateFormfields(map, marker);
          }
        });
        map.on("click", moveOrPlaceMarker);
      }

      App.Map.addInvestmentsMarkers(investmentsMarkers, createMarker);
      App.Map.addGeozones(map, geozoneLayers);

      map.addLayer(markers);

      // ES5 Safe Object Merging (No Spread Operator)
      layerControl = $.extend({"Markers": markers}, geozoneLayers);

      L.control.layers(null, layerControl).addTo(map);
    },
    leafletMap: function(element) {
      var centerData, mapCenterLatLng, map;

      centerData = App.Map.centerData(element);
      mapCenterLatLng = new L.LatLng(centerData.lat, centerData.long);
      map = L.map(element.id, { scrollWheelZoom: false }).setView(mapCenterLatLng, centerData.zoom);
      map.on("focus", function() {
        map.scrollWheelZoom.enable();
      });
      map.on("blur mouseout", function() {
        map.scrollWheelZoom.disable();
      });

      return map;
    },
    attributionPrefix: function() {
      return '<a href="https://leafletjs.com" title="A JavaScript library for interactive maps">Leaflet</a>';
    },
    markerData: function(element) {
      var dataCoordinates, formCoordinates, inputs, latitude, longitude;
      inputs = App.Map.coordinatesInputs(element);

      dataCoordinates = {
        lat: $(element).data("marker-latitude"),
        long: $(element).data("marker-longitude")
      };
      formCoordinates = {
        lat: inputs.lat.val(),
        long: inputs.long.val(),
        zoom: inputs.zoom.val()
      };

      if (App.Map.validCoordinates(formCoordinates)) {
        latitude = formCoordinates.lat;
        longitude = formCoordinates.long;
      } else if (App.Map.validCoordinates(dataCoordinates)) {
        latitude = dataCoordinates.lat;
        longitude = dataCoordinates.long;
      }

      return {
        lat: latitude,
        long: longitude,
        zoom: formCoordinates.zoom
      };
    },
    centerData: function(element) {
      var markerCoordinates, latitude, longitude, zoom;

      markerCoordinates = App.Map.markerData(element);

      if (App.Map.validCoordinates(markerCoordinates)) {
        latitude = markerCoordinates.lat;
        longitude = markerCoordinates.long;
      } else {
        latitude = $(element).data("map-center-latitude");
        longitude = $(element).data("map-center-longitude");
      }

      if (App.Map.validZoom(markerCoordinates.zoom)) {
        zoom = markerCoordinates.zoom;
      } else {
        zoom = $(element).data("map-zoom");
      }

      return {
        lat: latitude,
        long: longitude,
        zoom: zoom
      };
    },
    coordinatesInputs: function(element) {
      return {
        lat: $($(element).data("latitude-input-selector")),
        long: $($(element).data("longitude-input-selector")),
        zoom: $($(element).data("zoom-input-selector"))
      };
    },
    updateFormfields: function(map, marker) {
      var inputs = App.Map.coordinatesInputs(map._container);

      // ES5 Safe (Using var instead of const)
      var normalizedLatLng = marker.getLatLng().wrap();

      inputs.lat.val(normalizedLatLng.lat);
      inputs.long.val(normalizedLatLng.lng);
      inputs.zoom.val(map.getZoom());
    },
    clearFormfields: function(element) {
      var inputs = App.Map.coordinatesInputs(element);

      inputs.lat.val("");
      inputs.long.val("");
      inputs.zoom.val("");
    },
    addInvestmentsMarkers: function (markersData, createMarker) {
      if (markersData) {
        if (typeof markersData === 'object' && !Array.isArray(markersData)) {
          Object.keys(markersData).forEach(function (layerName) {
            markersData[layerName].forEach(function (coordinates) {
              if (App.Map.validCoordinates(coordinates)) {
                var marker = createMarker(coordinates.lat, coordinates.long, coordinates.color, coordinates.icon);
                marker.options.id = coordinates.investment_id;
                marker.bindPopup(App.Map.getPopupContent(coordinates));
              }
            });
          });
        } else if (Array.isArray(markersData)) {
          markersData.forEach(function (coordinates) {
            if (App.Map.validCoordinates(coordinates)) {
              var marker = createMarker(coordinates.lat, coordinates.long, coordinates.color, coordinates.icon);
              marker.options.id = coordinates.investment_id;
              marker.bindPopup(App.Map.getPopupContent(coordinates));
            }
          });
        }
      }
    },
    cleanInvestmentCoordinates: function(element) {
      var clean_markers, markers;
      markers = $(element).attr("data-marker-investments-coordinates");
      if (markers != null) {
        clean_markers = markers.replace(/-?(\*+)/g, null);
        $(element).attr("data-marker-investments-coordinates", clean_markers);
      }
    },
    addAttribution: function(map) {
      var element, mapAttribution, mapTilesProvider;

      element = map._container;
      mapTilesProvider = $(element).data("map-tiles-provider");
      mapAttribution = $(element).data("map-tiles-provider-attribution");

      map.attributionControl.setPrefix(App.Map.attributionPrefix());
      L.tileLayer(mapTilesProvider, { attribution: mapAttribution }).addTo(map);
    },
    addGeozones: function(map, geozoneLayers) {
      var geozones = $(map._container).data("geozones");

      if (geozones) {
        geozones.forEach(function(geozone) {
          App.Map.addGeozone(geozone, map, geozoneLayers);
        });
      }
    },
    addGeozone: function(geozone, map, geozoneLayers) {
      var geojsonData = JSON.parse(geozone.outline_points);

      var geoJsonLayer = L.geoJSON(geojsonData, {
        style: function(feature) {
          return {
            color: geozone.color || feature.properties.color || "blue",
            fillOpacity: 0.3,
            className: "map-polygon"
          };
        },
        onEachFeature: function(feature, layer) {
          if (feature.properties.headings || geozone.headings) {
            var headings = feature.properties.headings || geozone.headings;
            layer.bindPopup(headings.join("<br>"));
          }
        }
      });

      // ES5 Safe String Concatenation
      var layerName = (geozone.headings && geozone.headings.length > 0)
        ? geozone.headings.join(", ")
        : "Geozone " + (Object.keys(geozoneLayers).length + 1);

      geozoneLayers[layerName] = geoJsonLayer;
      geoJsonLayer.addTo(map);
    },
    getPopupContent: function(data) {
      return "<a href='" + data.link + "'>" + data.title + '</a>';
    },
    validZoom: function(zoom) {
      return App.Map.isNumeric(zoom);
    },
    validCoordinates: function(coordinates) {
      return App.Map.isNumeric(coordinates.lat) && App.Map.isNumeric(coordinates.long);
    },
    isNumeric: function(n) {
      return !isNaN(parseFloat(n)) && isFinite(n);
    }
  };
}).call(this);
