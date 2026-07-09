/* eslint-env es6 */
(function () {
  "use strict";
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
      let createMarker;
      let editable;
      let investmentsMarkers;
      let map;
      let marker;
      let markerClustering;
      let markerData;
      let removeMarker;
      let removeMarkerSelector;
      let markers;
      let moveOrPlaceMarker;
      const geozoneLayers = {};
      let layerControl = {};

      App.Map.cleanInvestmentCoordinates(element);
      removeMarkerSelector = $(element).data("marker-remove-selector");
      investmentsMarkers = $(element).data("marker-investments-coordinates");
      editable = $(element).data("marker-editable");
      markerClustering = $(element).data("marker-clustering");

      markers = markerClustering ? L.markerClusterGroup({chunkedLoading: true}) : L.layerGroup();

      createMarker = function (latitude, longitude, titleText) {
        let newMarker;
        let markerLatLng;
        let cleanTitle;
        markerLatLng = new L.LatLng(latitude, longitude);
        cleanTitle = titleText || "Map Location Indicator";

        const markerIcon = L.divIcon({
          className: "map-marker",
          iconSize: [30, 30],
          iconAnchor: [15, 40],
          html: '<div class="map-icon" tabindex="0" role="img" aria-label="' + cleanTitle + '"></div>'
        });

        newMarker = L.marker(markerLatLng, {
          icon: markerIcon,
          draggable: editable,
          title: cleanTitle
        });

        if (editable) {
          newMarker.on("dragend", function () {
            App.Map.updateFormfields(map, newMarker);
          });
        }
        markers.addLayer(newMarker);
        return newMarker;
      };

      removeMarker = function () {
        if (marker) {
          map.removeLayer(marker);
          marker = null;
        }
        App.Map.clearFormfields(element);
      };

      moveOrPlaceMarker = function (e) {
        if (marker) {
          marker.setLatLng(e.latlng);
        } else {
          marker = createMarker(e.latlng.lat, e.latlng.lng);
        }
        App.Map.updateFormfields(map, marker);
      };

      map = App.Map.leafletMap(element);
      App.Map.maps.push(map);
      const baseMaps = App.Map.setupBaseLayers(map, element);

      markerData = App.Map.markerData(element);
      if (markerData.lat && markerData.long && !investmentsMarkers) {
        marker = createMarker(markerData.lat, markerData.long, markerData.title);
      }

      if (editable) {
        $(removeMarkerSelector).on("click", removeMarker);
        map.on("zoomend", function () {
          if (marker) {
            App.Map.updateFormfields(map, marker);
          }
        });
        map.on("click", moveOrPlaceMarker);
      }

      App.Map.addInvestmentsMarkers(investmentsMarkers, createMarker);
      App.Map.addGeozones(map, geozoneLayers);

      map.addLayer(markers);

      if (investmentsMarkers && investmentsMarkers.length > 0) {
        try {
          map.fitBounds(markers.getBounds(), {padding: [40, 40], maxZoom: 15});
        } catch (err) {
          return false;
        }
      }

      layerControl = Object.assign({"Markers": markers}, geozoneLayers);
      L.control.layers(baseMaps, layerControl).addTo(map);
      L.control.scale({position: "bottomleft", metric: true, imperial: true}).addTo(map);

      // SILENT ADMIN CAPTURE: Listen for base layer changes
      map.on("baselayerchange", function (e) {
        // Find the map container, go up to its parent form, and ONLY update the hidden field inside that specific form
        const defaultLayerInput = $(map._container).closest("form").find("input[name='default_base_layer']");

        if (defaultLayerInput.length) {
          defaultLayerInput.val(e.name);
        }
      });
    },
    leafletMap: function (element) {
      let centerData;
      let mapCenterLatLng;
      let map;

      centerData = App.Map.centerData(element);
      mapCenterLatLng = new L.LatLng(centerData.lat, centerData.long);

      map = L.map(element.id, {
        scrollWheelZoom: false,
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
      return '<a href="https://leafletjs.com" title="A JS library for maps">Leaflet</a>';
    },
    markerData: function (element) {
      let dataCoordinates;
      let formCoordinates;
      let inputs;
      let latitude;
      let longitude;
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
        zoom: formCoordinates.zoom,
        title: dataCoordinates.title
      };
    },
    centerData: function (element) {
      let markerCoordinates;
      let latitude;
      let longitude;
      let zoom;

      markerCoordinates = App.Map.markerData(element);

      if (App.Map.validCoordinates(markerCoordinates)) {
        latitude = markerCoordinates.lat;
        longitude = markerCoordinates.long;
      } else {
        latitude = $(element).data("map-center-latitude");
        longitude = $(element).data("map-center-longitude");
      }

      if (App.Map.validZoom(markerCoordinates.zoom)) {
        zoom = markerCoordinates.zoom; // <--- FIXED HERE
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

      inputs.lat.val(marker.getLatLng().lat);
      inputs.long.val(marker.getLatLng().lng);
      inputs.zoom.val(map.getZoom());
    },
    clearFormfields: function (element) {
      const inputs = App.Map.coordinatesInputs(element);

      inputs.lat.val("");
      inputs.long.val("");
      inputs.zoom.val("");
    },
    addInvestmentsMarkers: function (markers, createMarker) {
      if (markers) {
        markers.forEach(function (coordinates) {
          let marker;

          if (App.Map.validCoordinates(coordinates)) {
            marker = createMarker(coordinates.lat, coordinates.long, coordinates.title);
            marker.options.id = coordinates["investment_id"];
            marker.bindPopup(App.Map.getPopupContent(coordinates));
          }
        });
      }
    },
    cleanInvestmentCoordinates: function (element) {
      let clean_markers;
      let markers;
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

      // 1. Default Consul configured map
      const defaultLayer = L.tileLayer(mapTilesProvider, {attribution: mapAttribution});

      // 2. Clean Minimalist (Light) - CartoDB Positron
      const cartoLight = L.tileLayer("https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png", {
        attribution: "&copy; <a href='https://www.openstreetmap.org/copyright'>OSM</a> contributors &copy; <a href='https://carto.com/attributions'>CARTO</a>"
      });

      // 3. High Contrast (Dark) - CartoDB Dark Matter
      const cartoDark = L.tileLayer("https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png", {
        attribution: "&copy; <a href='https://www.openstreetmap.org/copyright'>OSM</a> contributors &copy; <a href='https://carto.com/attributions'>CARTO</a>"
      });

      // 4. Community & Infrastructure - Humanitarian OpenStreetMap
      const osmHumanitarian = L.tileLayer("https://{s}.tile.openstreetmap.fr/hot/{z}/{x}/{y}.png", {
        attribution: "&copy; <a href='https://www.openstreetmap.org/copyright'>OSM</a> contributors, Tiles style by <a href='https://www.hotosm.org/'>HOT</a>"
      });

      // 5. Esri World Imagery (Satellite)
      const satelliteLayer = L.tileLayer("https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}", {
        attribution: "Tiles &copy; Esri &mdash; Source: Esri, i-cubed, USDA, USGS, AEX, GeoEye, Getmapping, Aerogrid, IGN, IGP, UPR-EGP, and the GIS User Community"
      });

      // 6. OpenTopoMap (Terrain)
      const terrainLayer = L.tileLayer("https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png", {
        attribution: "Map data: &copy; OpenStreetMap contributors, SRTM | Map style: &copy; OpenTopoMap (CC-BY-SA)"
      });

      // Group all layers into the return object
      const baseLayers = {
        "Standard Map": defaultLayer,
        "Clean Minimalist (Light)": cartoLight,
        "High Contrast (Dark)": cartoDark,
        "Community & Infrastructure": osmHumanitarian,
        "Satellite View": satelliteLayer,
        "Terrain View": terrainLayer
      };

      // Check the element for a user-configured default layer string
      const targetDefault = $(element).data("map-default-base-layer");

      // If a valid custom default was found, mount it. Otherwise fallback to standard.
      if (targetDefault && baseLayers[targetDefault]) {
        baseLayers[targetDefault].addTo(map);
      } else {
        defaultLayer.addTo(map);
      }

      return baseLayers;
    },
    addGeozones: function (map, geozoneLayers) {
      const geozones = $(map._container).data("geozones");

      if (geozones) {
        geozones.forEach(function (geozone) {
          App.Map.addGeozone(geozone, map, geozoneLayers);
        });
      }
    },
    addGeozone: function (geozone, map, geozoneLayers) {
      const geojsonData = JSON.parse(geozone["outline_points"]);

      const geoJsonLayer = L.geoJSON(geojsonData, {
        style: function (feature) {
          return {
            color: geozone.color || feature.properties.color || "blue",
            fillOpacity: 0.3,
            className: "map-polygon"
          };
        },
        onEachFeature: function (feature, layer) {
          if (feature.properties.headings || geozone["headings"]) {
            const headings = feature.properties.headings || geozone["headings"];
            layer.bindPopup(headings.join("<br>"));
          }
        }
      });

      const headingsArray = geozone["headings"];
      const layerName = (headingsArray && headingsArray.length > 0)
        ? headingsArray.join(", ")
        : "Geozone " + (Object.keys(geozoneLayers).length + 1);

      geozoneLayers[layerName] = geoJsonLayer;
      geoJsonLayer.addTo(map);
    },
    getPopupContent: function (data) {
      return "<a href='" + data.link + "'>" + data.title + "</a>";
    },
    validZoom: function (zoom) {
      return App.Map.isNumeric(zoom);
    },
    validCoordinates: function (coordinates) {
      return App.Map.isNumeric(coordinates.lat) && App.Map.isNumeric(coordinates.long);
    },
    isNumeric: function (n) {
      return !isNaN(parseFloat(n)) && isFinite(n);
    }
  };
}).call(this);
