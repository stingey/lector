import { Controller } from "@hotwired/stimulus"

// Reading surface behaviour.
//
// Hovering a word shows its grammar instantly from data attributes already in the
// DOM: no request, no waiting. Clicking loads the full card into a Turbo frame,
// which is the only path that can reach the network.
const DEFAULT_SIZE = 1.125

export default class extends Controller {
  static targets = ["tip", "card", "bookmarkCount"]
  static values = { sizeKey: { type: String, default: "lector:reading-size" } }

  // Reading sizes in rem, from comfortable-small to large-print.
  static SIZES = [0.9375, 1.0, 1.125, 1.25, 1.4, 1.5625, 1.75]

  connect() {
    this.applyStoredSize()
    this.revealAnchoredWord()
    this.onFrameLoad = this.handleFrameLoad.bind(this)
    this.onKeydown = this.handleKeydown.bind(this)
    this.onDocumentClick = this.handleDocumentClick.bind(this)
    this.onResize = this.positionCard.bind(this)
    document.addEventListener("turbo:frame-load", this.onFrameLoad)
    document.addEventListener("keydown", this.onKeydown)
    document.addEventListener("click", this.onDocumentClick)
    window.addEventListener("resize", this.onResize)
  }

  disconnect() {
    document.removeEventListener("turbo:frame-load", this.onFrameLoad)
    document.removeEventListener("keydown", this.onKeydown)
    document.removeEventListener("click", this.onDocumentClick)
    window.removeEventListener("resize", this.onResize)
  }

  // ----- words -----

  select(event) {
    const word = event.target.closest(".w")
    if (!word) return

    event.preventDefault()
    this.hideTip()
    this.markActive(word)

    // Held as a reference rather than read back off the DOM later: the card arrives
    // asynchronously, and by then a class could have been cleared by a close.
    this.activeWord = word
    this.cardTarget.src = `/tokens/${word.dataset.tokenId}`
  }

  hover(event) {
    const word = event.target.closest(".w")
    if (!word) return

    const lemma = word.dataset.lemma
    const grammar = word.dataset.grammar
    if (!lemma && !grammar) return

    const parts = []
    if (lemma && lemma.toLowerCase() !== word.textContent.toLowerCase()) {
      parts.push(`<span class="tip__lemma">${escapeHtml(lemma)}</span>`)
    }
    if (grammar) parts.push(`<span class="tip__grammar">${escapeHtml(grammar)}</span>`)
    if (parts.length === 0) return

    this.tipTarget.innerHTML = parts.join("<br>")
    this.positionTip(word)
    this.tipTarget.classList.add("tip--visible")
  }

  unhover(event) {
    if (event.target.closest(".w")) this.hideTip()
  }

  positionTip(word) {
    const box = word.getBoundingClientRect()
    const tip = this.tipTarget

    tip.style.visibility = "hidden"
    tip.classList.add("tip--visible")
    const tipBox = tip.getBoundingClientRect()
    tip.classList.remove("tip--visible")
    tip.style.visibility = ""

    let left = box.left + box.width / 2 - tipBox.width / 2
    left = Math.max(8, Math.min(left, window.innerWidth - tipBox.width - 8))

    const above = box.top - tipBox.height - 8
    const top = above > 8 ? above : box.bottom + 8

    tip.style.left = `${left}px`
    tip.style.top = `${top}px`
  }

  hideTip() {
    this.tipTarget.classList.remove("tip--visible")
  }

  markActive(word) {
    this.element.querySelectorAll(".w--active").forEach((el) => el.classList.remove("w--active"))
    word.classList.add("w--active")
  }

  closeCard(event) {
    if (event) event.preventDefault()
    this.activeWord = null
    this.cardTarget.removeAttribute("src")
    this.cardTarget.innerHTML = ""
    this.element.querySelectorAll(".w--active").forEach((el) => el.classList.remove("w--active"))
  }

  // Clicking away closes the card. Clicking another word is left alone, because that
  // click is already opening the next card and closing first would only flicker.
  handleDocumentClick(event) {
    if (!this.cardTarget.hasAttribute("src")) return
    if (event.target.closest(".word-card") || event.target.closest(".w")) return

    this.closeCard()
  }

  // ----- placing the card against its word -----

  // Anchored below the word, or above it when the card would run off the bottom. The
  // measurements are viewport-relative and the card is positioned in document
  // coordinates, so it then scrolls with the passage it belongs to.
  positionCard() {
    const card = this.cardTarget.querySelector(".word-card")
    const word = this.activeWord
    if (!card || !word) return

    // On a phone the card is a sheet pinned by CSS, so any inline position must go.
    if (window.matchMedia("(max-width: 640px)").matches) {
      card.removeAttribute("style")
      card.classList.remove("word-card--above")
      card.classList.add("word-card--placed")
      return
    }

    const gap = 8
    const rect = word.getBoundingClientRect()
    const viewport = document.documentElement
    const { offsetWidth: width, offsetHeight: height } = card

    // The reader bar is stuck to the bottom of the viewport, so the space it occupies is
    // not space the card can use: ignoring it would tuck the card underneath the bar.
    const bar = this.element.querySelector(".reader-bar")
    const room = {
      below: viewport.clientHeight - (bar ? bar.offsetHeight : 0) - rect.bottom,
      above: rect.top
    }
    const above = room.below < height + gap && room.above > room.below

    const left = clamp(rect.left + rect.width / 2 - width / 2, gap, viewport.clientWidth - width - gap)
    const top = above ? rect.top - height - gap : rect.bottom + gap

    card.classList.toggle("word-card--above", above)
    card.style.left = `${left + window.scrollX}px`
    card.style.top = `${top + window.scrollY}px`

    // Keep the caret over the word, but never off the end of the card.
    const caret = clamp(rect.left + rect.width / 2 - left, 16, width - 16)
    card.style.setProperty("--caret-x", `${caret}px`)

    card.classList.add("word-card--placed")
  }

  // ----- reacting to a word being saved or removed -----

  handleFrameLoad(event) {
    const frame = event.target
    if (!frame.id) return

    // The card is placed when it arrives, and again whenever anything inside it comes
    // back, since the translation landing or a button changing shape alters its height
    // and so whether it still fits below the word.
    if (frame.id === "word_card" || frame.closest(".word-card")) {
      // Dismissed while the request was still in flight: drop it rather than showing a
      // card for a word the reader has already moved on from.
      if (!this.activeWord) return this.closeCard()

      this.positionCard()
    }

    if (frame.id.startsWith("bank_")) {
      const marker = frame.querySelector("[data-bank-lemma]")
      if (marker) this.repaintLemma(marker.dataset.bankLemma, marker.dataset.bankStatus)
    }

    if (frame.id.startsWith("bookmark_")) {
      const marker = frame.querySelector("[data-bookmark-token]")
      if (marker) {
        this.repaintBookmark(marker.dataset.bookmarkToken, marker.dataset.bookmarkPlaced === "true")
        this.updateBookmarkCount(marker.dataset.bookmarkTotal)
      }
    }
  }

  // Repaints every conjugation of the word on the current page immediately, so the
  // effect of saving a word is visible without a reload.
  repaintLemma(lemmaId, status) {
    if (!lemmaId) return

    this.element.querySelectorAll(`.w[data-lemma-id="${lemmaId}"]`).forEach((word) => {
      word.classList.remove("w--learning", "w--known")
      if (status) word.classList.add(`w--${status}`)
    })
  }

  // A bookmark is one occurrence, so only the word that was marked changes.
  repaintBookmark(tokenId, placed) {
    const word = this.element.querySelector(`.w[data-token-id="${tokenId}"]`)
    if (word) word.classList.toggle("w--bookmarked", placed)
  }

  // The bar shows a count for the whole book, which this page cannot work out on its
  // own, so the server sends the new total back with the button.
  updateBookmarkCount(total) {
    if (!this.hasBookmarkCountTarget || total === undefined) return

    this.bookmarkCountTarget.textContent = Number(total) > 0 ? total : ""
  }

  // Arriving from a bookmark, the browser has already scrolled to the word, but on a
  // wall of prose that is not enough to find it: centre it and flash it once.
  revealAnchoredWord() {
    const id = window.location.hash.slice(1)
    if (!id) return

    const word = this.element.querySelector(`#${CSS.escape(id)}`)
    if (!word) return

    word.scrollIntoView({ block: "center" })
    word.classList.add("w--found")
    setTimeout(() => word.classList.remove("w--found"), 2000)
  }

  // ----- reading comfort -----

  larger() { this.stepSize(1) }
  smaller() { this.stepSize(-1) }

  // Discrete steps rather than a fractional nudge, so one press is a visible change.
  // The column width follows the size in CSS, which keeps the line length steady.
  stepSize(direction) {
    const sizes = this.constructor.SIZES
    const current = this.currentSize()
    const nearest = sizes.reduce(
      (best, size, index) => (Math.abs(size - current) < Math.abs(sizes[best] - current) ? index : best),
      0
    )

    this.applySize(sizes[Math.min(sizes.length - 1, Math.max(0, nearest + direction))])
  }

  currentSize() {
    const declared = getComputedStyle(document.documentElement).getPropertyValue("--reading-size")
    return parseFloat(declared) || DEFAULT_SIZE
  }

  applySize(size) {
    document.documentElement.style.setProperty("--reading-size", `${size}rem`)
    localStorage.setItem(this.sizeKeyValue, String(size))
  }

  applyStoredSize() {
    const stored = parseFloat(localStorage.getItem(this.sizeKeyValue))
    if (stored) this.applySize(stored)
  }

  handleKeydown(event) {
    if (event.metaKey || event.ctrlKey || event.altKey) return
    const typing = /^(INPUT|TEXTAREA|SELECT)$/.test(document.activeElement?.tagName || "")
    if (typing) return

    if (event.key === "Escape") return this.closeCard()

    const target = event.key === "ArrowRight" ? "next" : event.key === "ArrowLeft" ? "prev" : null
    if (!target) return

    const link = this.element.querySelector(`[data-page="${target}"]`)
    if (link) link.click()
  }
}

function escapeHtml(value) {
  const div = document.createElement("div")
  div.textContent = value
  return div.innerHTML
}

function clamp(value, min, max) {
  return Math.max(min, Math.min(value, max))
}
