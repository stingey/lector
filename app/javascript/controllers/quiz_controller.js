import { Controller } from "@hotwired/stimulus"

// Reveals the answer without a server round trip, and lets the four grade buttons
// be driven from the keyboard the way every SRS reviewer expects.
export default class extends Controller {
  static targets = ["answer", "reveal"]

  connect() {
    this.onKeydown = this.handleKeydown.bind(this)
    document.addEventListener("keydown", this.onKeydown)
  }

  disconnect() {
    document.removeEventListener("keydown", this.onKeydown)
  }

  reveal() {
    this.answerTarget.hidden = false
    this.revealTarget.hidden = true
  }

  get revealed() {
    return !this.answerTarget.hidden
  }

  handleKeydown(event) {
    if (event.metaKey || event.ctrlKey || event.altKey) return
    if (/^(INPUT|TEXTAREA|SELECT)$/.test(document.activeElement?.tagName || "")) return

    if (!this.revealed) {
      if (event.key === " " || event.key === "Enter") {
        event.preventDefault()
        this.reveal()
      }
      return
    }

    const index = ["1", "2", "3", "4"].indexOf(event.key)
    if (index === -1) return

    const button = this.answerTarget.querySelectorAll("form button")[index]
    if (button) {
      event.preventDefault()
      button.click()
    }
  }
}
