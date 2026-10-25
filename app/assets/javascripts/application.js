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
      if (index === 99) add.disabled = true;
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
