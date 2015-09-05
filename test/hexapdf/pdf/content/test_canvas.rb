# -*- encoding: utf-8 -*-

require 'test_helper'
require 'hexapdf/pdf/content/canvas'
require 'hexapdf/pdf/document'
require 'hexapdf/pdf/content/processor'
require 'hexapdf/pdf/content/parser'

describe HexaPDF::PDF::Content::Canvas do
  before do
    @recorder = TestHelper::OperatorRecorder.new
    @processor = HexaPDF::PDF::Content::Processor.new({}, renderer: @recorder)
    @processor.operators.clear
    @parser = HexaPDF::PDF::Content::Parser.new

    @doc = HexaPDF::PDF::Document.new
    @doc.config['graphic_object.arc.max_curves'] = 4
    @page = @doc.pages.add_page
    @canvas = HexaPDF::PDF::Content::Canvas.new(@page, content: :replace)
  end

  # Asserts that the content string contains the operators.
  def assert_operators(content, operators)
    @recorder.operations.clear
    @parser.parse(content, @processor)
    assert_equal(operators, @recorder.operators)
  end

  # Asserts that a specific operator is invoked when the block is executed.
  def assert_operator_invoked(op, *args)
    mock = Minitest::Mock.new
    if args.empty?
      mock.expect(:invoke, nil) { true }
      mock.expect(:serialize, '') { true }
    else
      mock.expect(:invoke, nil, [@canvas] + args)
      mock.expect(:serialize, '', [@canvas.instance_variable_get(:@serializer)] + args)
    end
    op_before = @canvas.instance_variable_get(:@operators)[op]
    @canvas.instance_variable_get(:@operators)[op] = mock
    yield
    assert(mock.verify)
  ensure
    @canvas.instance_variable_get(:@operators)[op] = op_before
  end

  describe "initialize" do
    module ContentStrategyTests
      extend Minitest::Spec::DSL

      it "content strategy replace: new content replaces existing content" do
        @context.contents = 'Some content here'
        canvas = HexaPDF::PDF::Content::Canvas.new(@context, content: :replace)
        canvas.save_graphics_state
        assert_operators(@context.contents, [[:save_graphics_state]])
      end

      it "content strategy append: new content is appended" do
        assert_raises(HexaPDF::Error) do
          HexaPDF::PDF::Content::Canvas.new(@context, content: :append)
        end
        skip
      end

      it "content strategy prepend: new content is prepended" do
        assert_raises(HexaPDF::Error) do
          HexaPDF::PDF::Content::Canvas.new(@context, content: :prepend)
        end
        skip
      end
    end

    describe "with Page as context" do
      include ContentStrategyTests

      before do
        @context = @doc.pages.page(0)
      end
    end

    describe "with Form as context" do
      include ContentStrategyTests

      before do
        @context = @doc.add(Subtype: :Form)
      end
    end
  end

  describe "resources" do
    it "returns the resources of the context object" do
      assert_equal(@page.resources, @canvas.resources)
    end
  end

  describe "save_graphics_state" do
    it "invokes the operator implementation" do
      assert_operator_invoked(:q) { @canvas.save_graphics_state }
    end

    it "is serialized correctly when no block is used" do
      @canvas.save_graphics_state
      assert_operators(@page.contents, [[:save_graphics_state]])
    end

    it "is serialized correctly when a block is used" do
      @canvas.save_graphics_state { }
      assert_operators(@page.contents, [[:save_graphics_state], [:restore_graphics_state]])
    end
  end

  describe "restore_graphics_state" do
    it "invokes the operator implementation" do
      assert_operator_invoked(:Q) { @canvas.restore_graphics_state }
    end

    it "is serialized correctly" do
      @canvas.graphics_state.save
      @canvas.restore_graphics_state
      assert_operators(@page.contents, [[:restore_graphics_state]])
    end
  end

  describe "transform" do
    it "invokes the operator implementation" do
      assert_operator_invoked(:cm, 1, 2, 3, 4, 5, 6) { @canvas.transform(1, 2, 3, 4, 5, 6) }
    end

    it "is serialized correctly when no block is used" do
      @canvas.transform(1, 2, 3, 4, 5, 6)
      assert_operators(@page.contents, [[:concatenate_matrix, [1, 2, 3, 4, 5, 6]]])
    end

    it "is serialized correctly when a block is used" do
      @canvas.transform(1, 2, 3, 4, 5, 6) {}
      assert_operators(@page.contents, [[:save_graphics_state],
                                        [:concatenate_matrix, [1, 2, 3, 4, 5, 6]],
                                        [:restore_graphics_state]])
    end
  end

  describe "rotate" do
    it "can rotate around the origin" do
      @canvas.rotate(90)
      assert_operators(@page.contents, [[:concatenate_matrix, [0, 1, -1, 0, 0, 0]]])
    end

    it "can rotate about an arbitrary point" do
      @canvas.rotate(90, origin: [100, 200])
      assert_operators(@page.contents, [[:concatenate_matrix, [0.0, 1.0, -1.0, 0.0, 300.0, 100.0]]])
    end
  end

  describe "scale" do
    it "can scale from the origin" do
      @canvas.scale(5, 10)
      assert_operators(@page.contents, [[:concatenate_matrix, [5, 0, 0, 10, 0, 0]]])
    end

    it "can scale from an arbitrary point" do
      @canvas.scale(5, 10, origin: [100, 200])
      assert_operators(@page.contents, [[:concatenate_matrix, [5, 0, 0, 10, -400, -1800]]])
    end

    it "works with a single scale factor" do
      @canvas.scale(5)
      assert_operators(@page.contents, [[:concatenate_matrix, [5, 0, 0, 5, 0, 0]]])
    end
  end

  describe "translate" do
    it "translates the origin" do
      @canvas.translate(100, 200)
      assert_operators(@page.contents, [[:concatenate_matrix, [1, 0, 0, 1, 100, 200]]])
    end
  end

  describe "skew" do
    it "can skew from the origin" do
      @canvas.skew(45, 0)
      assert_operators(@page.contents, [[:concatenate_matrix, [1, 1, 0, 1, 0, 0]]])
    end

    it "can skew from an arbitrary point" do
      @canvas.skew(45, 0, origin: [100, 200])
      assert_operators(@page.contents, [[:concatenate_matrix, [1, 1, 0, 1, 0, -100]]])
    end
  end

  describe "private gs_getter_setter" do
    it "returns the current value when used with a nil argument" do
      @canvas.graphics_state.line_width = 5
      assert_equal(5, @canvas.send(:gs_getter_setter, :line_width, :w, nil))
    end

    it "returns the canvas object when used with a non-nil argument or a block" do
      assert_equal(@canvas, @canvas.send(:gs_getter_setter, :line_width, :w, 15))
      assert_equal(@canvas, @canvas.send(:gs_getter_setter, :line_width, :w, 15) {})
    end

    it "invokes the operator implementation when a non-nil argument is used" do
      assert_operator_invoked(:w, 5) { @canvas.send(:gs_getter_setter, :line_width, :w, 5) }
      assert_operator_invoked(:w, 15) { @canvas.send(:gs_getter_setter, :line_width, :w, 15) {} }
    end

    it "doesn't add an operator if the value is equal to the current one" do
      @canvas.send(:gs_getter_setter, :line_width, :w,
                   @canvas.send(:gs_getter_setter, :line_width, :w, nil))
      assert_operators(@page.contents, [])
    end

    it "always saves and restores the graphics state if a block is used" do
      @canvas.send(:gs_getter_setter, :line_width, :w,
                   @canvas.send(:gs_getter_setter, :line_width, :w, nil)) {}
      assert_operators(@page.contents, [[:save_graphics_state], [:restore_graphics_state]])
    end

    it "is serialized correctly when no block is used" do
      @canvas.send(:gs_getter_setter, :line_width, :w, 5)
      assert_operators(@page.contents, [[:set_line_width, [5]]])
    end

    it "is serialized correctly when a block is used" do
      @canvas.send(:gs_getter_setter, :line_width, :w, 5) do
        @canvas.send(:gs_getter_setter, :line_width, :w, 15)
      end
      assert_operators(@page.contents, [[:save_graphics_state],
                                        [:set_line_width, [5]],
                                        [:set_line_width, [15]],
                                        [:restore_graphics_state]])
    end

    it "fails if a block is given without an argument" do
      assert_raises(HexaPDF::Error) { @canvas.send(:gs_getter_setter, :line_width, :w, nil) {} }
    end
  end

  # Asserts that the method +name+ invoked with +values+ invokes the #gs_getter_setter helper method
  # with the +name+, +operator+ and +expected_value+ as arguments.
  def assert_gs_getter_setter(name, operator, expected_value, *values)
    args = [name, operator, expected_value]
    assert_method_invoked(@canvas, :gs_getter_setter, args, check_block: true) do
      @canvas.send(name, *values) {}
    end
    assert_respond_to(@canvas, name)
  end

  describe "line_width" do
    it "uses the gs_getter_setter implementation" do
      assert_gs_getter_setter(:line_width, :w, 5, 5)
      assert_gs_getter_setter(:line_width, :w, nil, nil)
    end
  end

  describe "line_cap_style" do
    it "uses the gs_getter_setter implementation" do
      assert_gs_getter_setter(:line_cap_style, :J, 1, :round)
      assert_gs_getter_setter(:line_cap_style, :J, nil, nil)
    end
  end

  describe "line_join_style" do
    it "uses the gs_getter_setter implementation" do
      assert_gs_getter_setter(:line_join_style, :j, 1, :round)
      assert_gs_getter_setter(:line_join_style, :j, nil, nil)
    end
  end

  describe "miter_limit" do
    it "uses the gs_getter_setter implementation" do
      assert_gs_getter_setter(:miter_limit, :M, 15, 15)
      assert_gs_getter_setter(:miter_limit, :M, nil, nil)
    end
  end

  describe "line_dash_pattern" do
    it "uses the gs_getter_setter implementation" do
      assert_gs_getter_setter(:line_dash_pattern, :d, nil, nil)
      assert_gs_getter_setter(:line_dash_pattern, :d,
                              HexaPDF::PDF::Content::LineDashPattern.new, 0)
      assert_gs_getter_setter(:line_dash_pattern, :d,
                              HexaPDF::PDF::Content::LineDashPattern.new([5]), 5)
      assert_gs_getter_setter(:line_dash_pattern, :d,
                              HexaPDF::PDF::Content::LineDashPattern.new([5], 2), 5, 2)
      assert_gs_getter_setter(:line_dash_pattern, :d,
                              HexaPDF::PDF::Content::LineDashPattern.new([5, 3], 2), [5, 3], 2)
      assert_gs_getter_setter(:line_dash_pattern, :d,
                              HexaPDF::PDF::Content::LineDashPattern.new([5, 3], 2),
                              HexaPDF::PDF::Content::LineDashPattern.new([5, 3], 2))
    end
  end

  describe "rendering_intent" do
    it "uses the gs_getter_setter implementation" do
      assert_gs_getter_setter(:rendering_intent, :ri, :Perceptual, :Perceptual)
      assert_gs_getter_setter(:rendering_intent, :ri, nil, nil)
    end
  end

  describe "opacity" do
    it "returns the current values when no argument/nil arguments are provided" do
      assert_equal({fill_alpha: 1.0, stroke_alpha: 1.0}, @canvas.opacity)
    end

    it "returns the canvas object when at least one non-nil argument is provided" do
      assert_equal(@canvas, @canvas.opacity(fill_alpha: 0.5))
    end

    it "invokes the operator implementation when at least one non-nil argument is used" do
      assert_operator_invoked(:gs, :GS1) do
        @canvas.opacity(fill_alpha: 1.0, stroke_alpha: 0.5)
      end
    end

    it "doesn't add an operator if the values are not really changed" do
      @canvas.opacity(fill_alpha: 1.0, stroke_alpha: 1.0)
      assert_operators(@page.contents, [])
    end

    it "always saves and restores the graphics state if a block is used" do
      @canvas.opacity(fill_alpha: 1.0, stroke_alpha: 1.0) {}
      assert_operators(@page.contents, [[:save_graphics_state], [:restore_graphics_state]])
    end

    it "adds the needed entry to the /ExtGState resources dictionary" do
      @canvas.graphics_state.alpha_source = true
      @canvas.opacity(fill_alpha: 0.5, stroke_alpha: 0.7)
      assert_equal({Type: :ExtGState, CA: 0.7, ca: 0.5, AIS: false},
                   @canvas.resources.ext_gstate(:GS1))
    end

    it "is serialized correctly when no block is used" do
      @canvas.opacity(fill_alpha: 0.5, stroke_alpha: 0.7)
      assert_operators(@page.contents, [[:set_graphics_state_parameters, [:GS1]]])
    end

    it "is serialized correctly when a block is used" do
      @canvas.send(:gs_getter_setter, :line_width, :w, 5) do
        @canvas.send(:gs_getter_setter, :line_width, :w, 15)
      end
      assert_operators(@page.contents, [[:save_graphics_state],
                                        [:set_line_width, [5]],
                                        [:set_line_width, [15]],
                                        [:restore_graphics_state]])
    end

    it "fails if a block is given without an argument" do
      assert_raises(HexaPDF::Error) { @canvas.opacity {} }
    end
  end

  describe "private color_getter_setter" do
    def invoke(*params, &block)
      @canvas.send(:color_getter_setter, :stroke_color, params, :RG, :G, :K, :CS, :SCN, &block)
    end

    it "returns the current value when used with no argument" do
      color = @canvas.graphics_state.stroke_color
      assert_equal(color, invoke)
    end

    it "returns the canvas when used with a non-nil argument and no block" do
      assert_equal(@canvas, invoke(255))
      assert_equal(@canvas, invoke(255) {})
    end

    it "doesn't add an operator if the value is equal to the current one" do
      invoke(0.0)
      assert_operators(@page.contents, [])
    end

    it "always saves and restores the graphics state if a block is used" do
      invoke(0.0) {}
      assert_operators(@page.contents, [[:save_graphics_state], [:restore_graphics_state]])
    end

    it "adds an unknown color space to the resource dictionary" do
      invoke(HexaPDF::PDF::Content::ColorSpace::Universal.new([:Pattern, :DeviceRGB]).color(:Name))
      assert_equal([:Pattern, :DeviceRGB], @page.resources.color_space(:CS1).definition)
    end

    it "is serialized correctly when no block is used" do
      invoke(102)
      invoke([102])
      invoke("6600FF")
      invoke(102, 0, 255)
      invoke(0, 20, 40, 80)
      invoke(HexaPDF::PDF::Content::ColorSpace::Universal.new([:Pattern]).color(:Name))
      assert_operators(@page.contents, [[:set_device_gray_stroking_color, [0.4]],
                                        [:set_device_rgb_stroking_color, [0.4, 0, 1]],
                                        [:set_device_cmyk_stroking_color, [0, 0.2, 0.4, 0.8]],
                                        [:set_stroking_color_space, [:CS1]],
                                        [:set_stroking_color, [:Name]]])
    end

    it "is serialized correctly when a block is used" do
      invoke(102) { invoke(255) }
      assert_operators(@page.contents, [[:save_graphics_state],
                                        [:set_device_gray_stroking_color, [0.4]],
                                        [:set_device_gray_stroking_color, [1.0]],
                                        [:restore_graphics_state]])
    end

    it "fails if a block is given without an argument" do
      assert_raises(HexaPDF::Error) { invoke {} }
    end

    it "fails if an unsupported number of component values is provided" do
      assert_raises(HexaPDF::Error) { invoke(5, 5) }
    end
  end

  # Asserts that the method +name+ invoked with +values+ invokes the #color_getter_setter helper
  # method with the +expected_values+ as arguments.
  def assert_color_getter_setter(name, expected_values, *values)
    assert_method_invoked(@canvas, :color_getter_setter, expected_values, check_block: true) do
      @canvas.send(name, *values) {}
    end
  end

  describe "stroke_color" do
    it "uses the color_getter_setter implementation" do
      assert_color_getter_setter(:stroke_color, [:stroke_color, [255], :RG, :G, :K, :CS, :SCN], 255)
      assert_color_getter_setter(:stroke_color, [:stroke_color, [], :RG, :G, :K, :CS, :SCN])
    end
  end

  describe "fill_color" do
    it "uses the color_getter_setter implementation" do
      assert_color_getter_setter(:fill_color, [:fill_color, [255], :rg, :g, :k, :cs, :scn], 255)
      assert_color_getter_setter(:fill_color, [:fill_color, [], :rg, :g, :k, :cs, :scn])
    end
  end

  describe "move_to" do
    it "invokes the operator implementation" do
      assert_operator_invoked(:m, 5, 6) { @canvas.move_to(5, 6) }
      assert_operator_invoked(:m, 5, 6) { @canvas.move_to([5, 6]) }
    end

    it "returns the canvas object" do
      assert_equal(@canvas, @canvas.move_to(5, 6))
    end
  end

  describe "line_to" do
    it "invokes the operator implementation" do
      assert_operator_invoked(:l, 5, 6) { @canvas.line_to(5, 6) }
      assert_operator_invoked(:l, 5, 6) { @canvas.line_to([5, 6]) }
    end

    it "returns the canvas object" do
      assert_equal(@canvas, @canvas.line_to(5, 6))
    end
  end

  describe "curve_to" do
    it "invokes the operator implementation" do
      assert_operator_invoked(:c, 5, 6, 7, 8, 9, 10) { @canvas.curve_to(9, 10, p1: [5, 6], p2: [7, 8]) }
      assert_operator_invoked(:v, 7, 8, 9, 10) { @canvas.curve_to(9, 10, p2: [7, 8]) }
      assert_operator_invoked(:y, 5, 6, 9, 10) { @canvas.curve_to(9, 10, p1: [5, 6]) }
    end

    it "returns the canvas object" do
      assert_equal(@canvas, @canvas.curve_to(5, 6, p1: [7, 8]))
    end

    it "raises an error if both control points are omitted" do
      assert_raises(HexaPDF::Error) { @canvas.curve_to(9, 10) }
    end
  end

  describe "rectangle" do
    it "invokes the operator implementation when radius == 0" do
      assert_operator_invoked(:re, 5, 10, 15, 20) { @canvas.rectangle(5, 10, 15, 20) }
      assert_operator_invoked(:re, 5, 10, 15, 20) { @canvas.rectangle([5, 10], 15, 20) }
    end

    it "invokes the polygon method when radius != 0" do
      args = [0, 0, 10, 0, 10, 10, 0, 10, radius: 5]
      assert_method_invoked(@canvas, :polygon, args) do
        @canvas.rectangle(0, 0, 10, 10, radius: 5)
      end
    end

    it "returns the canvas object" do
      assert_equal(@canvas, @canvas.rectangle(5, 6, 7, 8))
    end
  end

  describe "close_subpath" do
    it "invokes the operator implementation" do
      assert_operator_invoked(:h) { @canvas.close_subpath }
    end

    it "returns the canvas object" do
      assert_equal(@canvas, @canvas.close_subpath)
    end
  end

  describe "line" do
    it "serializes correctly" do
      @canvas.line(1, 2, 3, 4)
      assert_operators(@page.contents, [[:move_to, [1, 2]], [:line_to, [3, 4]]])
    end

    it "returns the canvas object" do
      assert_equal(@canvas, @canvas.line(1, 2, 3, 4))
    end
  end

  describe "polyline" do
    it "serializes correctly" do
      @canvas.polyline(1, 2, 3, 4, [5, 6])
      assert_operators(@page.contents, [[:move_to, [1, 2]], [:line_to, [3, 4]], [:line_to, [5, 6]]])
    end

    it "returns the canvas object" do
      assert_equal(@canvas, @canvas.polyline(1, 2, 3, 4))
    end

    it "fails if not enought points are supplied" do
      assert_raises(HexaPDF::Error) { @canvas.polyline(5, 6) }
    end

    it "fails if a y-coordinate is missing" do
      assert_raises(HexaPDF::Error) { @canvas.polyline(5, 6, 7, 8, 9) }
    end
  end

  describe "polygon" do
    it "serializes correctly with no radius" do
      @canvas.polygon(1, 2, 3, 4, [5, 6])
      assert_operators(@page.contents, [[:move_to, [1, 2]], [:line_to, [3, 4]],
                                        [:line_to, [5, 6]], [:close_subpath]])
    end

    it "serializes correctly with a radius" do
      @canvas.polygon(-1, -1, -1, 1, 1, 1, 1, -1, radius: 1)
      k = @canvas.class::KAPPA.round(6)
      assert_operators(@page.contents, [[:move_to, [-1, 0]],
                                        [:line_to, [-1, 0]], [:curve_to, [-1, k, -k, 1, 0, 1]],
                                        [:line_to, [0, 1]], [:curve_to, [k, 1, 1, k, 1, 0]],
                                        [:line_to, [1, 0]], [:curve_to, [1, -k, k, -1, 0, -1]],
                                        [:line_to, [0, -1]], [:curve_to, [-k, -1, -1, -k, -1, 0]],
                                        [:close_subpath]])
    end

    it "returns the canvas object" do
      assert_equal(@canvas, @canvas.polyline(1, 2, 3, 4, 5, 6))
    end
  end

  describe "circle" do
    it "uses arc for the hard work" do
      assert_method_invoked(@canvas, :arc, [5, 6, a: 7]) do
        @canvas.circle(5, 6, 7)
      end
    end

    it "serializes correctly" do
      @canvas.circle(0, 0, 1)
      @recorder.operations.clear
      @parser.parse(@page.contents, @processor)
      assert_equal([:move_to, :curve_to, :curve_to, :curve_to, :curve_to, :close_subpath],
                    @recorder.operators.map(&:first))
    end

    it "returns the canvas object" do
      assert_equal(@canvas, @canvas.circle(1, 2, 3))
    end
  end

  describe "ellipse" do
    it "uses arc for the hard work" do
      assert_method_invoked(@canvas, :ellipse, [5, 6, a: 7, b: 5, inclination: 10]) do
        @canvas.ellipse(5, 6, a: 7, b: 5, inclination: 10)
      end
    end

    it "serializes correctly" do
      @canvas.ellipse(0, 0, a: 10, b: 5, inclination: 10)
      @recorder.operations.clear
      @parser.parse(@page.contents, @processor)
      assert_equal([:move_to, :curve_to, :curve_to, :curve_to, :curve_to, :close_subpath],
                    @recorder.operators.map(&:first))
    end

    it "returns the canvas object" do
      assert_equal(@canvas, @canvas.circle(1, 2, 3))
    end
  end

  describe "arc" do
    it "serializes correctly" do
      @canvas.arc(0, 0, a: 1, b: 1, start_angle: 0, end_angle: 360, inclination: 0)
      @canvas.arc(0, 0, a: 1, b: 1, start_angle: 0, end_angle: 360, sweep: false, inclination: 0)
      assert_operators(@page.contents, [[:move_to, [1, 0]],
                                        [:curve_to, [1, 0.548584, 0.548584, 1, 0, 1]],
                                        [:curve_to, [-0.548584, 1, -1, 0.548584, -1, 0]],
                                        [:curve_to, [-1, -0.548584, -0.548584, -1, 0, -1]],
                                        [:curve_to, [0.548584, -1, 1, -0.548584, 1, 0]],
                                        [:move_to, [1, 0]],
                                        [:curve_to, [1, -0.548584, 0.548584, -1, 0, -1]],
                                        [:curve_to, [-0.548584, -1, -1, -0.548584, -1, 0]],
                                        [:curve_to, [-1, 0.548584, -0.548584, 1, 0, 1]],
                                        [:curve_to, [0.548584, 1, 1, 0.548584, 1, 0]]])
    end

    it "returns the canvas object" do
      assert_equal(@canvas, @canvas.arc(1, 2, a: 3))
    end
  end

  describe "graphic_object" do
    it "returns a new graphic object given a name" do
      arc = @canvas.graphic_object(:arc)
      assert_respond_to(arc, :draw)
      arc1 = @canvas.graphic_object(:arc)
      refute_same(arc, arc1)
    end

    it "returns a configured graphic object given a name" do
      arc = @canvas.graphic_object(:arc, cx: 10)
      assert_equal(10, arc.cx)
    end

    it "reconfigures the given graphic object" do
      arc = @canvas.graphic_object(:arc)
      arc1 = @canvas.graphic_object(arc, cx: 10)
      assert_same(arc, arc1)
      assert_equal(10, arc.cx)
    end
  end

  describe "draw" do
    it "draws the, optionally configured, graphic object onto the canvas" do
      obj = Object.new
      obj.define_singleton_method(:options) { @options }
      obj.define_singleton_method(:configure) {|**kwargs| @options = kwargs; self}
      obj.define_singleton_method(:draw) {|canvas| canvas.move_to(@options[:x], @options[:y])}
      @canvas.draw(obj, x: 5, y: 6)
      assert_operators(@page.contents, [[:move_to, [5, 6]]])
    end

    it "returns the canvas object" do
      assert_equal(@canvas, @canvas.draw(:arc))
    end
  end

  describe "path painting methods" do
    it "invokes the respective operator implementation" do
      assert_operator_invoked(:S) { @canvas.stroke }
      assert_operator_invoked(:s) { @canvas.close_stroke }
      assert_operator_invoked(:f) { @canvas.fill(:nonzero) }
      assert_operator_invoked(:'f*') { @canvas.fill(:even_odd) }
      assert_operator_invoked(:B) { @canvas.fill_stroke(:nonzero) }
      assert_operator_invoked(:'B*') { @canvas.fill_stroke(:even_odd) }
      assert_operator_invoked(:b) { @canvas.close_fill_stroke(:nonzero) }
      assert_operator_invoked(:'b*') { @canvas.close_fill_stroke(:even_odd) }
      assert_operator_invoked(:n) { @canvas.end_path }
    end

    it "returns the canvas object" do
      assert_equal(@canvas, @canvas.stroke)
      assert_equal(@canvas, @canvas.close_stroke)
      assert_equal(@canvas, @canvas.fill)
      assert_equal(@canvas, @canvas.fill_stroke)
      assert_equal(@canvas, @canvas.close_fill_stroke)
      assert_equal(@canvas, @canvas.end_path)
    end
  end

  describe "clip_path" do
    it "invokes the respective operator implementation" do
      assert_operator_invoked(:W) { @canvas.clip_path(:nonzero) }
      assert_operator_invoked(:'W*') { @canvas.clip_path(:even_odd) }
    end

    it "returns the canvas object" do
      assert_equal(@canvas, @canvas.clip_path)
    end
  end

  describe "xobject" do
    before do
      @image = @doc.add(Subtype: :Image, Width: 10, Height: 5)
      @image.source_path = File.join(TEST_DATA_DIR, 'images', 'gray.jpg')
      @form = @doc.add(Subtype: :Form, BBox: [100, 50, 200, 100])
    end

    it "can use any xobject specified via a filename" do
      xobject = @canvas.xobject(@image.source_path, at: [0, 0])
      assert_equal(xobject, @page.resources.xobject(:XO1))
    end

    it "can use any xobject specified via an IO object" do
      File.open(@image.source_path, 'rb') do |file|
        xobject = @canvas.xobject(file, at: [0, 0])
        assert_equal(xobject, @page.resources.xobject(:XO1))
      end
    end

    it "can use an already existing xobject" do
      xobject = @canvas.xobject(@image, at: [0, 0])
      assert_equal(xobject, @page.resources.xobject(:XO1))
    end

    it "correctly serializes the image with no options" do
      @canvas.xobject(@image, at: [1, 2])
      assert_operators(@page.contents, [[:save_graphics_state],
                                        [:concatenate_matrix, [10, 0, 0, 5, 1, 2]],
                                        [:paint_xobject, [:XO1]],
                                        [:restore_graphics_state]])
    end

    it "correctly serializes the image with just the width given" do
      @canvas.image(@image, at: [1, 2], width: 20)
      assert_operators(@page.contents, [[:save_graphics_state],
                                        [:concatenate_matrix, [20, 0, 0, 10, 1, 2]],
                                        [:paint_xobject, [:XO1]],
                                        [:restore_graphics_state]])
    end

    it "correctly serializes the image with just the height given" do
      @canvas.image(@image, at: [1, 2], height: 10)
      assert_operators(@page.contents, [[:save_graphics_state],
                                        [:concatenate_matrix, [20, 0, 0, 10, 1, 2]],
                                        [:paint_xobject, [:XO1]],
                                        [:restore_graphics_state]])
    end

    it "correctly serializes the image with both width and height given" do
      @canvas.image(@image, at: [1, 2], width: 10, height: 20)
      assert_operators(@page.contents, [[:save_graphics_state],
                                        [:concatenate_matrix, [10, 0, 0, 20, 1, 2]],
                                        [:paint_xobject, [:XO1]],
                                        [:restore_graphics_state]])
    end

    it "correctly serializes the form with no options" do
      @canvas.xobject(@form, at: [1, 2])
      assert_operators(@page.contents, [[:save_graphics_state],
                                        [:concatenate_matrix, [1, 0, 0, 1, -99, -48]],
                                        [:paint_xobject, [:XO1]],
                                        [:restore_graphics_state]])
    end

    it "correctly serializes the form with just the width given" do
      @canvas.image(@form, at: [1, 2], width: 50)
      assert_operators(@page.contents, [[:save_graphics_state],
                                        [:concatenate_matrix, [0.5, 0, 0, 0.5, -99, -48]],
                                        [:paint_xobject, [:XO1]],
                                        [:restore_graphics_state]])
    end

    it "correctly serializes the form with just the height given" do
      @canvas.image(@form, at: [1, 2], height: 10)
      assert_operators(@page.contents, [[:save_graphics_state],
                                        [:concatenate_matrix, [0.2, 0, 0, 0.2, -99, -48]],
                                        [:paint_xobject, [:XO1]],
                                        [:restore_graphics_state]])
    end

    it "correctly serializes the form with both width and height given" do
      @canvas.image(@form, at: [1, 2], width: 50, height: 10)
      assert_operators(@page.contents, [[:save_graphics_state],
                                        [:concatenate_matrix, [0.5, 0, 0, 0.2, -99, -48]],
                                        [:paint_xobject, [:XO1]],
                                        [:restore_graphics_state]])
    end
  end
end