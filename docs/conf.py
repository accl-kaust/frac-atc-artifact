# Configuration file for the Sphinx documentation builder.
# https://www.sphinx-doc.org/en/master/usage/configuration.html

project = "fRAC"
copyright = "2026, fRAC contributors"
author = "fRAC contributors"

extensions = [
    "sphinx_rtd_theme",
    "sphinx.ext.autosectionlabel",
]

# Give every section an implicit label, namespaced by document, so that
# :ref:`text <document:Section Title>` resolves and is checked at build time.
autosectionlabel_prefix_document = True

templates_path = ["_templates"]
exclude_patterns = ["_build", "Thumbs.db", ".DS_Store"]

# -- HTML output -------------------------------------------------------------

html_theme = "sphinx_rtd_theme"
html_static_path = []

html_theme_options = {
    "collapse_navigation": False,
    "sticky_navigation": True,
    "navigation_depth": 4,
    "titles_only": False,
    "prev_next_buttons_location": "both",
    "style_external_links": True,
}

# Syntax highlighting default for bare :: literal blocks.
highlight_language = "text"

# Pygments' Tcl lexer cannot parse backslash line-continuations in the Vivado
# commands in build-and-deployment.rst; it falls back to relaxed mode and still
# renders. Suppress only this cosmetic class so that -W keeps failing the build
# on real problems such as broken :ref:/:doc: targets.
suppress_warnings = ["misc.highlighting_failure"]
