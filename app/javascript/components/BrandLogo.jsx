import React, { useState } from 'react'

// Practice logo. Shows the real image the moment one is placed at public/brand/logo.png
// (PNG or SVG with a transparent background); until then it renders a clean gold wordmark that
// mirrors the logo. No build step needed — just drop the file in.
export default function BrandLogo({ className = 'h-12', wordmarkClass = 'text-xl' }) {
  const [haveImage, setHaveImage] = useState(true)
  if (haveImage) {
    return (
      <img
        src="/brand/logo.png"
        alt="Dr Chalita le Roux — dentist & aesthetic practitioner"
        className={className}
        onError={() => setHaveImage(false)}
      />
    )
  }
  return (
    <div className="leading-none">
      <span className={`font-semibold tracking-wide text-brand-primary ${wordmarkClass}`}>
        Dr Chalita <span className="font-normal italic">le</span> Roux
      </span>
      <p className="mt-1 text-[10px] uppercase tracking-[0.2em] text-brand-muted">dentist &amp; aesthetic practitioner</p>
    </div>
  )
}
