# frozen_string_literal: true

# CRUD shared by every book. Each book is a namespace with one controller
# that names its model, its title and its permitted params; views live in
# the book's own folder, with shared shells in app/views/book_entries.
class BookEntriesController < ApplicationController
  class_attribute :entry_class, :book_title, :book_key

  before_action :set_world
  before_action :require_world_editor, except: %i[index show]
  before_action :set_entry, only: %i[show edit update destroy]

  helper_method :entry_class, :book_title, :book_key, :entry_path, :entries_path

  def index
    @entries = ordered(scope)
  end

  def show; end

  def new
    @entry = scope.new
  end

  def edit; end

  def create
    @entry = scope.new(entry_params)
    forget_generation(@entry)
    if @entry.save
      redirect_to entry_path(@entry), notice: "#{@entry.name} was added to the #{book_title}."
    else
      render :new, status: :unprocessable_content
    end
  end

  def update
    @entry.assign_attributes(entry_params.except(:slug))
    forget_generation(@entry)
    if @entry.save
      redirect_to entry_path(@entry), notice: "#{@entry.name} was updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    if @entry.destroy
      redirect_to entries_path, notice: "#{@entry.name} was removed from the #{book_title}.", status: :see_other
    else
      redirect_to entry_path(@entry), alert: @entry.errors.full_messages.to_sentence, status: :see_other
    end
  end

  private

  def set_world
    @world = World.find_by!(slug: params[:world_slug])
  end

  def set_entry
    @entry = scope.find_by!(slug: params[:slug])
  end

  def scope
    @world.public_send(entry_class.model_name.plural)
  end

  def ordered(relation)
    relation.alphabetical
  end

  def entry_path(entry)
    polymorphic_path([ @world, book_key, entry ])
  end

  def entries_path
    polymorphic_path([ @world, book_key, entry_class ])
  end

  # Every param any primitive takes; the model keeps only the ones the
  # chosen primitive uses.
  def effect_fields
    [ "primitive", *Battle::PRIMITIVE_PARAMS.values.flat_map { |spec| spec[:required] + spec[:optional] }.uniq ]
  end

  # An uploaded image wasn't generated: drop the seed and recipe of the old one.
  def forget_generation(entry)
    return unless entry.attachment_changes.key?("image")

    entry.image_seed = nil
    entry.image_prompt = nil
    entry.image_recipe = nil
  end

  # Art fields every book entry shares (§3.3, §8).
  def art_params
    colour = entry_class.column_names.include?("colour") ? [ :colour ] : []
    [ :image, *colour, { variant: %i[hue scale flip] } ]
  end
end
