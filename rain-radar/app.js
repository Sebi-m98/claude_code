// RegenRadar Deutschland
// Uses RainViewer API (free, no key needed) + Leaflet.js

(function () {
    'use strict';

    // --- Config ---
    const GERMANY_CENTER = [51.2, 10.4];
    const DEFAULT_ZOOM = 7;
    const STEPS_PER_DAY = 96; // 24h * 4 (every 15 min)
    const STEP_MINUTES = 15;
    const RAINVIEWER_API = 'https://api.rainviewer.com/public/weather-maps.json';

    // --- State ---
    let map;
    let radarLayer = null;
    let rainviewerData = null; // { past: [], nowcast: [] }
    let allTimestamps = []; // combined sorted unix timestamps from RainViewer

    // --- DOM refs ---
    const slider = document.getElementById('time-slider');
    const timeDisplay = document.getElementById('current-time');
    const btnBack = document.getElementById('btn-back');
    const btnForward = document.getElementById('btn-forward');
    const btnNow = document.getElementById('btn-now');
    const noDataEl = document.getElementById('no-data');

    // --- Init ---
    function init() {
        initMap();
        loadRainViewerData();
        initSlider();
        initControls();

        // Refresh RainViewer data every 5 minutes
        setInterval(loadRainViewerData, 5 * 60 * 1000);
    }

    function initMap() {
        map = L.map('map', {
            center: GERMANY_CENTER,
            zoom: DEFAULT_ZOOM,
            zoomControl: true,
            attributionControl: true,
        });

        // Light base map similar to WetterOnline style
        L.tileLayer('https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png', {
            attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OSM</a> &copy; <a href="https://carto.com/">CARTO</a> | Radar: <a href="https://www.rainviewer.com/">RainViewer</a>',
            subdomains: 'abcd',
            maxZoom: 18,
        }).addTo(map);
    }

    // --- RainViewer API ---
    async function loadRainViewerData() {
        try {
            const response = await fetch(RAINVIEWER_API);
            const data = await response.json();
            rainviewerData = data;

            // Combine past and nowcast timestamps
            const past = (data.radar?.past || []).map(f => f.time);
            const nowcast = (data.radar?.nowcast || []).map(f => f.time);
            allTimestamps = [...past, ...nowcast].sort((a, b) => a - b);

            // Update display for current slider position
            updateRadarForSlider();
        } catch (err) {
            console.error('Failed to load RainViewer data:', err);
        }
    }

    function findClosestTimestamp(targetUnix) {
        if (allTimestamps.length === 0) return null;

        let closest = allTimestamps[0];
        let minDiff = Math.abs(targetUnix - closest);

        for (const ts of allTimestamps) {
            const diff = Math.abs(targetUnix - ts);
            if (diff < minDiff) {
                minDiff = diff;
                closest = ts;
            }
        }

        // Only match if within 15 minutes
        if (minDiff > 15 * 60) return null;
        return closest;
    }

    function setRadarLayer(timestamp) {
        if (radarLayer) {
            map.removeLayer(radarLayer);
            radarLayer = null;
        }

        if (!timestamp || !rainviewerData) {
            noDataEl.classList.remove('hidden');
            return;
        }

        noDataEl.classList.add('hidden');

        const tileSize = 256;
        const colorScheme = 2; // Universal Blue (similar to WetterOnline)
        const smooth = 1;
        const snow = 1;

        radarLayer = L.tileLayer(
            `${rainviewerData.host}/v2/radar/${timestamp}/${tileSize}/{z}/{x}/{y}/${colorScheme}/${smooth}_${snow}.png`,
            {
                opacity: 0.7,
                zIndex: 100,
                maxZoom: 18,
            }
        ).addTo(map);
    }

    // --- Slider Logic ---
    function initSlider() {
        // Set slider to current time
        const nowStep = getCurrentTimeStep();
        slider.value = nowStep;
        updateTimeDisplay(nowStep);

        slider.addEventListener('input', function () {
            const step = parseInt(this.value, 10);
            updateTimeDisplay(step);
            updateRadarForSlider();
        });
    }

    function getCurrentTimeStep() {
        const now = new Date();
        const hours = now.getHours();
        const minutes = now.getMinutes();
        const totalMinutes = hours * 60 + minutes;
        return Math.round(totalMinutes / STEP_MINUTES);
    }

    function stepToTime(step) {
        const totalMinutes = step * STEP_MINUTES;
        const hours = Math.floor(totalMinutes / 60) % 24;
        const minutes = totalMinutes % 60;
        return {
            hours,
            minutes,
            label: `${String(hours).padStart(2, '0')}:${String(minutes).padStart(2, '0')}`,
        };
    }

    function stepToUnixTimestamp(step) {
        const now = new Date();
        const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate());
        const totalMinutes = step * STEP_MINUTES;
        return Math.floor(todayStart.getTime() / 1000) + totalMinutes * 60;
    }

    function updateTimeDisplay(step) {
        const time = stepToTime(step);
        timeDisplay.textContent = time.label;
    }

    function updateRadarForSlider() {
        const step = parseInt(slider.value, 10);
        const targetUnix = stepToUnixTimestamp(step);
        const closest = findClosestTimestamp(targetUnix);
        setRadarLayer(closest);
    }

    // --- Controls ---
    function initControls() {
        btnBack.addEventListener('click', function () {
            const current = parseInt(slider.value, 10);
            if (current > 0) {
                slider.value = current - 1;
                updateTimeDisplay(current - 1);
                updateRadarForSlider();
            }
        });

        btnForward.addEventListener('click', function () {
            const current = parseInt(slider.value, 10);
            if (current < STEPS_PER_DAY - 1) {
                slider.value = current + 1;
                updateTimeDisplay(current + 1);
                updateRadarForSlider();
            }
        });

        btnNow.addEventListener('click', function () {
            const nowStep = getCurrentTimeStep();
            slider.value = nowStep;
            updateTimeDisplay(nowStep);
            updateRadarForSlider();
        });

        // Keyboard controls
        document.addEventListener('keydown', function (e) {
            if (e.key === 'ArrowLeft') {
                btnBack.click();
                e.preventDefault();
            } else if (e.key === 'ArrowRight') {
                btnForward.click();
                e.preventDefault();
            } else if (e.key === ' ' || e.key === 'Home') {
                btnNow.click();
                e.preventDefault();
            }
        });
    }

    // --- Start ---
    document.addEventListener('DOMContentLoaded', init);
})();
