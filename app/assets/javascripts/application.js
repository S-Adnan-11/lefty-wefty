document.addEventListener("DOMContentLoaded", () => {
  const add = document.querySelector("#add-sale-line");
  if (add) {
    add.hidden = false;
    add.addEventListener("click", () => {
      const lines = document.querySelector("#sale-lines");
      const index = lines.children.length;
      if (index >= 100) return;
      const template = document.querySelector("#sale-line-template").innerHTML;
      lines.insertAdjacentHTML("beforeend", template.replaceAll("__INDEX__", index).replaceAll("__NUMBER__", index + 1));
      lines.lastElementChild.querySelector("select").focus();
      enhance(lines.lastElementChild);
      if (index === 99) add.disabled = true;
    });
  }
  const money = value => {
    const digits = value.toString().padStart(3, "0");
    return `₦${digits.slice(0, -2).replace(/\B(?=(\d{3})+(?!\d))/g, ",")}.${digits.slice(-2)}`;
  };
  function preview(line) {
    const price = line.querySelector("select")?.selectedOptions[0]?.dataset.priceMinor;
    const quantity = line.querySelector("input[type=number]")?.value;
    line.querySelector("[data-line-total]").textContent = price && /^[1-9][0-9]*$/.test(quantity) && BigInt(quantity) <= 2147483647n ? money(BigInt(price) * BigInt(quantity)) : "—";
  }
  function enhance(root) {
    root.querySelectorAll("[data-step]").forEach(button => {
      button.hidden = false;
      button.addEventListener("click", () => {
        const input = button.parentElement.querySelector("input");
        const min = Number(input.min), max = Number(input.max);
        if (input.value && !/^[0-9]+$/.test(input.value)) { input.focus(); return; }
        const next = input.value === "" ? min : Number(input.value) + Number(button.dataset.step);
        input.value = String(Math.min(max, Math.max(min, next)));
        input.dispatchEvent(new Event("input", {bubbles: true}));
      });
    });
    root.querySelectorAll("input[type=number]").forEach(input => input.addEventListener("wheel", event => event.preventDefault(), {passive: false}));
    root.querySelectorAll(".sale-line").forEach(line => {
      line.querySelector("[data-line-preview]").hidden = false;
      line.addEventListener("input", () => preview(line));
      line.addEventListener("change", () => preview(line));
      preview(line);
    });
  }
  enhance(document);
  document.querySelectorAll("[data-money]").forEach(input => {
    input.addEventListener("blur", () => {
      const text = input.value.trim();
      if (!/^(?:[0-9]+|[1-9][0-9]{0,2}(?:,[0-9]{3})+)(?:\.[0-9]{1,2})?$/.test(text) || text.length > 32) return;
      const [whole, fraction = ""] = text.replaceAll(",", "").split(".");
      input.value = whole.replace(/\B(?=(\d{3})+(?!\d))/g, ",") + "." + fraction.padEnd(2, "0");
    });
  });
  document.querySelectorAll("[data-help], [data-menu]").forEach(details => {
    const close = () => { details.open = false; details.querySelector("summary").focus(); };
    details.addEventListener("keydown", event => { if (event.key === "Escape") { event.preventDefault(); close(); } });
    const button = details.querySelector(".help-close");
    if (button) { button.hidden = false; button.addEventListener("click", close); }
    document.addEventListener("click", event => { if (!details.contains(event.target)) details.open = false; });
  });
  const logoInput = document.querySelector("[data-logo-input]");
  if (logoInput) {
    const frame = document.querySelector("#logo-preview");
    const original = frame.innerHTML;
    let url;
    logoInput.addEventListener("change", () => {
      if (url) URL.revokeObjectURL(url);
      frame.innerHTML = original;
      const status = document.querySelector("#logo-preview-status");
      const file = logoInput.files[0];
      status.textContent = "";
      if (!file) return;
      if (!["image/png", "image/jpeg", "image/webp"].includes(file.type) || file.size > 2097152) {
        status.textContent = "Choose a PNG, JPEG or WebP image up to 2 MB.";
        return;
      }
      url = URL.createObjectURL(file);
      const image = new Image();
      image.alt = "Selected logo preview";
      image.onload = () => { frame.replaceChildren(image); status.textContent = "Preview only. Save settings to keep this logo."; };
      image.onerror = () => { status.textContent = "This image could not be previewed. Choose a valid image."; };
      image.src = url;
    });
  }
  document.querySelectorAll("form[data-pending]").forEach(form => {
    form.addEventListener("submit", () => {
      form.setAttribute("aria-busy", "true");
      form.querySelectorAll("[type=submit]").forEach(button => { button.disabled = true; });
      const status = form.querySelector("[data-submission-status]");
      if (status) status.textContent = "Saving… Please wait.";
    });
  });
});
window.addEventListener("pageshow", () => {
  document.querySelectorAll("form[data-pending]").forEach(form => {
    form.removeAttribute("aria-busy");
    form.querySelectorAll("[type=submit]").forEach(button => { button.disabled = false; });
    const status = form.querySelector("[data-submission-status]");
    if (status) status.textContent = "";
  });
});
