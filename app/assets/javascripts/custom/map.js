/* eslint-env es6 */
(function () {
  "use strict";

  if (typeof App.Utils === "undefined") {
    App.Utils = {
      isNumeric: function (n) {
        return !isNaN(parseFloat(n)) && isFinite(n);
      }
    };
  }

  App.Map = {
    maps: [],
    initialize: function () {
      $("*[data-map]:visible").each(function () {
        App.Map.initializeMap(this);
      });
    },
    destroy: function () {
      App.Map.maps.forEach(function (map) {
        map.off();
        map.remove();
      });
      App.Map.maps = [];
    },
    initializeMap: function (element) {
      let createMarker, editable, geozoneLayers, investmentsMarkers, map, marker, markerClustering,
        markerData, markerIcon, moveOrPlaceMarker, removeMarker, removeMarkerSelector,
        layersToCreate, layerControlOverlays, globalBounds;

      App.Map.cleanInvestmentCoordinates(element);
      removeMarkerSelector = $(element).data("marker-remove-selector");
      investmentsMarkers = $(element).data("marker-investments-coordinates");
      editable = $(element).data("marker-editable");
      markerClustering = $(element).data("marker-clustering");

      marker = null;

      markerIcon = function (alt_text, color, icon) {
        const cleanTitle = alt_text || "Map Location Indicator";
        const pinColor = color || "#00cae9";

        let pinIcon = icon || "map-marker-alt";
        pinIcon = pinIcon.replace(/^(fas\s|far\s|fa\s|fa-)/, "");

        return L.divIcon({
          className: "map-marker",
          iconSize: [30, 30],
          iconAnchor: [15, 40],
          // Change the <i> tag to a <div> using our new custom prefix
          html: '<div class="map-icon" style="--marker-color: ' + pinColor + ';" tabindex="0" role="img" aria-label="' + cleanTitle + '">' +
            '<div class="custom-pin-icon-' + pinIcon + '"></div>' +
            '</div>'
        });
      };

      createMarker = function (latitude, longitude, targetLayerGroup, text, color, icon) {
        let newMarker, markerLatLng;
        markerLatLng = new L.LatLng(latitude, longitude);
        newMarker = L.marker(markerLatLng, {
          icon: markerIcon(text, color, icon),
          draggable: editable,
          title: text || "Map Location Indicator"
        });

        if (editable) {
          newMarker.on("dragend", function () {
            App.Map.updateFormfields(map, newMarker);
          });
        }
        targetLayerGroup.addLayer(newMarker);
        return newMarker;
      };

      removeMarker = function () {
        if (marker) {
          map.removeLayer(marker);
          marker = null;
        }
        App.Map.clearFormfields(element);
      };

      map = App.Map.leafletMap(element);
      App.Map.maps.push(map);

      const baseMaps = App.Map.setupBaseLayers(map, element);

      layersToCreate = {};
      layerControlOverlays = {};
      globalBounds = L.latLngBounds([]);

      if (Array.isArray(investmentsMarkers)) {
        layersToCreate["Markers"] = investmentsMarkers;
      } else if (typeof investmentsMarkers === "object" && investmentsMarkers !== null) {
        layersToCreate = investmentsMarkers;
      }

      Object.keys(layersToCreate).forEach(function (layerName) {
        let currentLayerGroup = markerClustering ? L.markerClusterGroup({chunkedLoading: true}) : L.layerGroup();
        let points = layersToCreate[layerName];

        points.forEach(function (point) {
          let customMarker;
          if (App.Map.validCoordinates(point)) {
            customMarker = createMarker(point.lat, point.long, currentLayerGroup, point.title, point.color, point.icon);
            customMarker.options.id = point.investment_id || point.id;
            customMarker.bindPopup(App.Map.getPopupContent(point));

            globalBounds.extend([point.lat, point.long]);
          }
        });

        map.addLayer(currentLayerGroup);
        layerControlOverlays[layerName] = currentLayerGroup;
      });

      markerData = App.Map.markerData(element);
      if (markerData.lat && markerData.long && !investmentsMarkers) {
        let fallbackGroup = L.layerGroup().addTo(map);
        marker = createMarker(markerData.lat, markerData.long, fallbackGroup, markerData.title);
        layerControlOverlays["Markers"] = fallbackGroup;
        globalBounds.extend([markerData.lat, markerData.long]);
      }

      if (editable) {
        $(removeMarkerSelector).on("click", removeMarker);
        map.on("zoomend", function () {
          if (marker) {
            App.Map.updateFormfields(map, marker);
          }
        });

        moveOrPlaceMarker = function (e) {
          let editingGroup = layerControlOverlays["Markers"] || L.layerGroup().addTo(map);
          layerControlOverlays["Markers"] = editingGroup;
          if (marker) {
            marker.setLatLng(e.latlng);
          } else {
            marker = createMarker(e.latlng.lat, e.latlng.lng, editingGroup);
          }
          App.Map.updateFormfields(map, marker);
        };
        map.on("click", moveOrPlaceMarker);
      }

      geozoneLayers = App.Map.geozoneLayers(map);
      App.Map.addGeozones(map, geozoneLayers);

      // Restore Object.assign for clean Leaflet object merging
      layerControlOverlays = Object.assign({}, layerControlOverlays, geozoneLayers);

      if (globalBounds.isValid()) {
        try {
          map.fitBounds(globalBounds, {padding: [40, 40], maxZoom: 15});
        } catch (err) {
        }
      }

      const layersControl = L.control.layers(null, layerControlOverlays, {position: "topright"}).addTo(map);
      const baseControl = L.control.layers(baseMaps, null, {position: "bottomright"}).addTo(map);
      L.control.scale({position: "bottomleft", metric: true, imperial: true}).addTo(map);

      $(layersControl.getContainer()).find('.leaflet-control-layers-list').prepend('<div class="layer-control-header">Layers</div>');
      $(baseControl.getContainer()).find('.leaflet-control-layers-list').prepend('<div class="layer-control-header">Maps</div>');

      map.on("baselayerchange", function (e) {
        const defaultLayerInput = $(map._container).closest("form").find("input[name='default_base_layer']");
        if (defaultLayerInput.length) {
          defaultLayerInput.val(e.name);
        }
      });
    },
    leafletMap: function (element) {
      let centerData, mapCenterLatLng, map;

      centerData = App.Map.centerData(element);
      mapCenterLatLng = new L.LatLng(centerData.lat, centerData.long);

      map = L.map(element.id, {
        scrollWheelZoom: false,
        maxZoom: 18,
        renderer: L.canvas()
      }).setView(mapCenterLatLng, centerData.zoom);

      map.on("focus", function () {
        map.scrollWheelZoom.enable();
      });
      map.on("blur mouseout", function () {
        map.scrollWheelZoom.disable();
      });

      return map;
    },
    attributionPrefix: function () {
      return '<a href="https://leafletjs.com" title="A JavaScript library for interactive maps">Leaflet</a>';
    },
    markerData: function (element) {
      let dataCoordinates, formCoordinates, inputs, latitude, longitude;
      inputs = App.Map.coordinatesInputs(element);

      dataCoordinates = {
        lat: $(element).data("marker-latitude"),
        long: $(element).data("marker-longitude"),
        title: $(element).data("marker-title")
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
        title: dataCoordinates.title,
        zoom: formCoordinates.zoom
      };
    },
    centerData: function (element) {
      let markerCoordinates, latitude, longitude, zoom;

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
    coordinatesInputs: function (element) {
      return {
        lat: $($(element).data("latitude-input-selector")),
        long: $($(element).data("longitude-input-selector")),
        zoom: $($(element).data("zoom-input-selector"))
      };
    },
    updateFormfields: function (map, marker) {
      const inputs = App.Map.coordinatesInputs(map._container);
      const normalizedLatLng = marker.getLatLng().wrap();

      inputs.lat.val(normalizedLatLng.lat);
      inputs.long.val(normalizedLatLng.lng);
      inputs.zoom.val(map.getZoom());
    },
    clearFormfields: function (element) {
      const inputs = App.Map.coordinatesInputs(element);
      inputs.lat.val("");
      inputs.long.val("");
      inputs.zoom.val("");
    },
    cleanInvestmentCoordinates: function (element) {
      let clean_markers, markers;
      markers = $(element).attr("data-marker-investments-coordinates");
      if (markers != null) {
        clean_markers = markers.replace(/-?(\*+)/g, null);
        $(element).attr("data-marker-investments-coordinates", clean_markers);
      }
    },
    setupBaseLayers: function (map, element) {
      const mapTilesProvider = $(element).data("map-tiles-provider");
      const mapAttribution = $(element).data("map-tiles-provider-attribution");

      map.attributionControl.setPrefix(App.Map.attributionPrefix());

      const defaultLayer = L.tileLayer(mapTilesProvider, {attribution: mapAttribution});

      const cartoLight = L.tileLayer("https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png", {
        attribution: "&copy; <a href='https://www.openstreetmap.org/copyright'>OSM</a> contributors &copy; <a href='https://carto.com/attributions'>CARTO</a>"
      });

      const cartoDark = L.tileLayer("https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png", {
        attribution: "&copy; <a href='https://www.openstreetmap.org/copyright'>OSM</a> contributors &copy; <a href='https://carto.com/attributions'>CARTO</a>"
      });

      const osmHumanitarian = L.tileLayer("https://{s}.tile.openstreetmap.fr/hot/{z}/{x}/{y}.png", {
        attribution: "&copy; <a href='https://www.openstreetmap.org/copyright'>OSM</a> contributors, Tiles style by <a href='https://www.hotosm.org/'>HOT</a>"
      });

      const satelliteLayer = L.tileLayer("https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}", {
        attribution: "Tiles &copy; Esri &mdash; Source: Esri, i-cubed, USDA, USGS, AEX, GeoEye, Getmapping, Aerogrid, IGN, IGP, UPR-EGP, and the GIS User Community"
      });

      const terrainLayer = L.tileLayer("https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png", {
        attribution: "Map data: &copy; OpenStreetMap contributors, SRTM | Map style: &copy; OpenTopoMap (CC-BY-SA)"
      });

      const baseLayers = {
        "Standard Map": defaultLayer,
        "Clean Minimalist (Light)": cartoLight,
        "High Contrast (Dark)": cartoDark,
        "Community & Infrastructure": osmHumanitarian,
        "Satellite View": satelliteLayer,
        "Terrain View": terrainLayer
      };

      const targetDefault = $(element).data("map-default-base-layer");

      if (targetDefault && baseLayers[targetDefault]) {
        baseLayers[targetDefault].addTo(map);
      } else {
        defaultLayer.addTo(map);
      }

      return baseLayers;
    },
    addGeozones: function (map, geozoneLayers) {
      $.each(geozoneLayers, function (_, geozoneLayer) {
        App.Map.addGeozone(map, geozoneLayer);
      });
    },
    geozoneLayers: function (map) {
      const geozones = $(map._container).data("geozones");
      const layers = {};

      if (geozones) {
        geozones.forEach(function (geozone) {
          if (geozone.outline_points) {
            let layerName = geozone.name;
            if (!layerName) {
              const headingsArray = geozone["headings"];
              layerName = (headingsArray && headingsArray.length > 0) ? headingsArray.join(", ") : "Geozone " + (Object.keys(layers).length + 1);
            }
            layers[layerName] = App.Map.geozoneLayer(geozone);
          }
        });
      }

      return layers;
    },
    geozoneLayer: function (geozone) {
      const geojsonData = JSON.parse(geozone.outline_points);

      return L.geoJSON(geojsonData, {
        style: function (feature) {
          return {
            color: feature.properties.color || geozone.color || "blue",
            fillOpacity: 0.3,
            className: "map-polygon"
          };
        },
        onEachFeature: function (feature, layer) {
          const headings = feature.properties.headings || geozone.headings;

          if (headings) {
            layer.bindPopup(headings.join("<br>"));
          }
        }
      });
    },
    addGeozone: function (map, geozoneLayer) {
      geozoneLayer.addTo(map);
    },
    getPopupContent: function (data) {
      return "<a href='" + data.link + "'>" + data.title + "</a>";
    },
    validZoom: function (zoom) {
      return App.Utils.isNumeric(zoom);
    },
    validCoordinates: function (coordinates) {
      return App.Utils.isNumeric(coordinates.lat) && App.Utils.isNumeric(coordinates.long);
    }
  };
}).call(this);
