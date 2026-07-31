class FeatureRegistry {
  constructor() {
    this.features = new Map();
  }

  register(id, definition) {
    if (!id || typeof definition?.run !== "function") {
      throw new Error("Feature requires id and run handler");
    }
    this.features.set(id, {
      id,
      description: definition.description || "",
      params: definition.params || {},
      run: definition.run,
    });
    return this;
  }

  get(id) {
    return this.features.get(id) || null;
  }

  list() {
    return Array.from(this.features.values()).map(({ id, description, params }) => ({
      id,
      description,
      params,
    }));
  }

  async run(id, mta, params = {}) {
    const feature = this.get(id);
    if (!feature) {
      const error = new Error(`Unknown feature: ${id}`);
      error.status = 404;
      throw error;
    }
    return feature.run(mta, params);
  }
}

module.exports = { FeatureRegistry };
