import { useEffect, useRef } from 'react';
import L from 'leaflet';
import type { Report, ReportDetail } from '../lib/types';
import { catLabel, REPORT_STATUS } from '../lib/format';

const JAKARTA: L.LatLngExpression = [-6.2, 106.82];

function markerClass(r: Report) {
  if (r.status === 'open') return 'open';
  if (r.status === 'acknowledged' || r.status === 'in_progress') return 'ack';
  return 'done';
}

const esc = (s: string) => s.replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`);

/**
 * Peta Leaflet + OpenStreetMap. Marker dikelola imperatif (bukan per render React)
 * supaya ratusan laporan realtime tidak membuat ulang layer.
 */
export function ReportMap({ reports, selected, trail, onSelect }: {
  reports: Report[]; selected: string | null; trail: ReportDetail['locations'] | null; onSelect: (id: string) => void;
}) {
  const el = useRef<HTMLDivElement>(null);
  const map = useRef<L.Map | null>(null);
  const markers = useRef(new Map<string, L.Marker>());
  const trailLayer = useRef<L.LayerGroup | null>(null);
  const fitted = useRef(false);
  const onSelectRef = useRef(onSelect);
  onSelectRef.current = onSelect;

  /** Pusatkan ke semua marker. Ditunda sampai kontainer punya ukuran: fit saat ukuran 0 membuat peta meleset (mis. ke laut). */
  const fitAll = (force = false) => {
    const m = map.current;
    if (!m || (fitted.current && !force) || !markers.current.size) return;
    const size = m.getSize();
    if (size.x < 50 || size.y < 50) return;
    fitted.current = true;
    const b = L.latLngBounds([...markers.current.values()].map((x) => x.getLatLng()));
    m.fitBounds(b.pad(0.15), { maxZoom: 15, animate: force });
  };

  useEffect(() => {
    if (!el.current) return;
    const m = L.map(el.current, { zoomControl: true, attributionControl: true }).setView(JAKARTA, 11);
    // Tile OSM standar; diredam lewat CSS (.leaflet-tile-pane) supaya marker SOS merah tidak tenggelam di antara simbol POI.
    L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
      maxZoom: 19, attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>',
    }).addTo(m);
    trailLayer.current = L.layerGroup().addTo(m);
    map.current = m;
    // Tombol "tampilkan semua laporan" di bawah kontrol zoom
    const FitCtl = L.Control.extend({
      onAdd: () => {
        const b = L.DomUtil.create('button', 'leaflet-bar map-fit');
        b.type = 'button';
        b.title = 'Tampilkan semua laporan';
        b.setAttribute('aria-label', 'Tampilkan semua laporan');
        b.innerHTML = '<svg viewBox="0 0 256 256" width="18" height="18" aria-hidden="true"><path fill="currentColor" d="M216 48v48a8 8 0 0 1-16 0V67.3l-42.3 42.4a8 8 0 0 1-11.4-11.4L188.7 56H160a8 8 0 0 1 0-16h48a8 8 0 0 1 8 8ZM98.3 146.3 56 188.7V160a8 8 0 0 0-16 0v48a8 8 0 0 0 8 8h48a8 8 0 0 0 0-16H67.3l42.4-42.3a8 8 0 0 0-11.4-11.4Z"/></svg>';
        L.DomEvent.disableClickPropagation(b);
        L.DomEvent.on(b, 'click', () => fitAll(true));
        return b;
      },
    });
    new FitCtl({ position: 'topleft' }).addTo(m);
    const ro = new ResizeObserver(() => { m.invalidateSize(); fitAll(); });
    ro.observe(el.current);
    return () => { ro.disconnect(); m.remove(); map.current = null; markers.current.clear(); };
  }, []);

  // sinkronkan marker
  useEffect(() => {
    const m = map.current;
    if (!m) return;
    const seen = new Set<string>();
    for (const r of reports) {
      if (!r.location) continue;
      seen.add(r.id);
      const cls = `sos-marker ${markerClass(r)}`;
      const ll: L.LatLngExpression = [r.location.lat, r.location.lng];
      const label = `${catLabel(r.category)} — ${REPORT_STATUS[r.status].label}`;
      let mk = markers.current.get(r.id);
      if (!mk) {
        mk = L.marker(ll, { icon: L.divIcon({ className: '', html: `<div class="${cls}"></div>`, iconSize: [20, 20], iconAnchor: [10, 10] }), title: label, keyboard: true, riseOnHover: true })
          .on('click', () => onSelectRef.current(r.id))
          .addTo(m);
        markers.current.set(r.id, mk);
      } else {
        mk.setLatLng(ll);
        mk.setIcon(L.divIcon({ className: '', html: `<div class="${cls}"></div>`, iconSize: [20, 20], iconAnchor: [10, 10] }));
        mk.options.title = label;
      }
      mk.setZIndexOffset(r.status === 'open' ? 1000 : r.id === selected ? 900 : 0);
      mk.bindTooltip(esc(label + (r.reporter.name ? ` · ${r.reporter.name}` : '')), { direction: 'top', offset: [0, -10] });
    }
    for (const [id, mk] of markers.current) if (!seen.has(id)) { mk.remove(); markers.current.delete(id); }

    fitAll();
  }, [reports, selected]);

  // fokus ke laporan terpilih
  useEffect(() => {
    const r = reports.find((x) => x.id === selected);
    const m = map.current;
    if (!r?.location || !m) return;
    const zoom = Math.max(m.getZoom(), 15);
    // Panel detail menutupi ±432 px sisi kanan peta (desktop); geser titik tengah supaya marker tetap terlihat.
    // >960 px = breakpoint CSS saat panel melayang di atas peta (di bawahnya panel jadi bottom sheet).
    const w = m.getSize().x;
    const shift = window.innerWidth > 960 ? Math.min(432, w - 120) / 2 : 0;
    const center = m.unproject(m.project([r.location.lat, r.location.lng], zoom).add([shift, 0]), zoom);
    m.flyTo(center, zoom, { duration: 0.6 });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [selected]);

  // jejak lokasi live
  useEffect(() => {
    const g = trailLayer.current;
    if (!g) return;
    g.clearLayers();
    if (trail && trail.length > 1) {
      L.polyline(trail.map((p) => [p.lat, p.lng] as L.LatLngTuple), { color: '#2563eb', weight: 3, opacity: 0.8, dashArray: '6 6' }).addTo(g);
    }
    const last = trail?.[trail.length - 1];
    if (last?.accuracy_m) L.circle([last.lat, last.lng], { radius: last.accuracy_m, color: '#2563eb', weight: 1, fillOpacity: 0.08 }).addTo(g);
  }, [trail]);

  return <div ref={el} className="map" role="region" aria-label="Peta lokasi laporan" />;
}
