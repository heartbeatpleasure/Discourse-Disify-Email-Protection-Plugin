import "./api-initializers/disify-email-protection-settings-button-fix";

export default {
  resource: "admin.adminPlugins",
  path: "/plugins",
  map() {
    this.route("disifyEmailProtection", { path: "/disify-email-protection" });
  },
};
