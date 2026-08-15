export default {
  resource: "admin.adminPlugins",
  path: "/plugins",
  map() {
    this.route("disifyEmailProtectionReview", {
      path: "/disify-email-protection-review",
    });
  },
};
