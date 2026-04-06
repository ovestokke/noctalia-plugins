# Air Quality

Displays real-time air quality data from the Open-Meteo API with EPA color coding.
Shows AQI index (US EPA or European scale) and pollutant breakdown for PM2.5, PM10, O3, NO2, CO, and SO2.

## Features

**Bar Widget**
- AQI number colored by level (EPA color scale)
- Tooltip with full pollutant breakdown
- Left click to open panel
- Right click for context menu
- Middle click to refresh

**Panel**
- Large AQI number with level indicator
- Location pill with last update time
- Pollutant rows with colored indicators
- Refresh and settings buttons

**Desktop Widget**
- Draggable AQI display with level and city
- PM2.5 and PM10 values
- Left click to open panel
- Middle click to refresh

**Settings**
- AQI scale: US AQI (EPA) or European AQI
- Location: use Noctalia location or custom coordinates
- Refresh interval (5-120 minutes)
- Bold text toggle

**IPC**
- Refresh: `qs -c noctalia-shell ipc call plugin:air-quality refresh`
- Toggle panel: `qs -c noctalia-shell ipc call plugin:air-quality toggle`

## Data Source

[Open-Meteo Air Quality API](https://open-meteo.com/)
