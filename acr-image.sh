#!/bin/bash
set -euo pipefail

function die {
  echo "Error: $@"
  exit 1
}

# image regular expression.
# e.g. garm123.azurecr.io/example:1.2.3
#      ^^^^^^^^^^^^^^^^^^ ^^^^^^^ ^^^^^
#      registry           name    tag
# NB the tag is optional.
IMAGE_REGEX='^([^\/]+)\/([^:]+)(:([^:]+))?$'

# validate the source image.
if [[ "$ACR_IMAGE_SOURCE_IMAGE" =~ $IMAGE_REGEX ]]; then
  source_registry="${BASH_REMATCH[1]}"
  source_name="${BASH_REMATCH[2]}"
  source_tag="${BASH_REMATCH[4]}"
  source_image="$source_registry/$source_name:$source_tag"
  if [ -z "$source_tag" ]; then
    die "Source image must have a tag."
  fi
else
  die "Invalid source image format."
fi

# validate the target image.
if [[ "$ACR_IMAGE_TARGET_IMAGE" =~ $IMAGE_REGEX ]]; then
  target_registry="${BASH_REMATCH[1]}"
  target_ecr_name="${target_registry%.azurecr.io}"
  target_name="${BASH_REMATCH[2]}"
  target_tag="${BASH_REMATCH[4]:-$source_tag}"
  target_image="$target_registry/$target_name:$target_tag"
  if [[ ! $target_registry =~ \.azurecr\.io$ ]]; then
    die "The target image is not an ACR repository."
  fi
else
  die "Invalid target image format."
fi

# login into the target acr.
acr_username="$(az acr credential show \
  --name "$target_ecr_name" \
  --query username \
  --output tsv)"
az acr credential show \
  --name "$target_ecr_name" \
  --query 'passwords[0].value' \
  --output tsv \
  | crane auth login \
    --username "$acr_username" \
    --password-stdin \
    "$target_registry"

# manage the image.
case "$ACR_IMAGE_COMMAND" in
  copy)
    crane copy \
      --allow-nondistributable-artifacts \
      --platform=linux/amd64 \
      "$source_image" \
      "$target_image"
    ;;
  delete)
    (
      set +e
      echo "Getting the "$target_image" image digest..."
      # NB with ACR, we cannot delete an image by tag due to the error:
      #     UNSUPPORTED: A manifest can only be deleted by digest
      #    so, we first get the digest, then delete that.
      result="$(crane digest "$target_image" 2>&1)"
      exit_code="$?"
      echo "$result"
      if [ "$exit_code" -ne '0' ]; then
        # treat the 'MANIFEST_UNKNOWN' error as success, because the image no
        # longer exists.
        unknown_manifest_regex='MANIFEST_UNKNOWN: manifest tagged by'
        if [[ "$result" =~ $unknown_manifest_regex ]]; then
          echo "NB The previous error was ignored because the image was already deleted."
          exit 0
        fi
        exit "$exit_code"
      fi
      target_image_manifest="$result"
      echo "Deleting the "$target_image@$target_image_manifest" image..."
      result="$(crane delete "$target_image@$target_image_manifest" 2>&1)"
      exit_code="$?"
      echo "$result"
      if [ "$exit_code" -ne '0' ]; then
        # TODO drop all the error-handling code around 'crane delete' if
        #      https://github.com/google/go-containerregistry/issues/1862
        #      is implemented. the goal is to simplify error handling once
        #      the issue is resolved.
        # treat the 'image not found' error as success. this error may occur
        # when someone manually deletes the image. from the script's viewpoint,
        # it is not considered an error, as the ultimate goal is to have a
        # deleted image. if it is already deleted, consider it a success.
        unknown_image_regex='MANIFEST_UNKNOWN: Requested image not found'
        if [[ "$result" =~ $unknown_image_regex ]]; then
          echo "NB The DELETE error was ignored because the image was already deleted."
          exit 0
        fi
        unknown_image_regex='MANIFEST_UNKNOWN: manifest .+ is not found'
        if [[ "$result" =~ $unknown_image_regex ]]; then
          echo "NB The DELETE error was ignored because the image was already deleted."
          exit 0
        fi
        # treat the 'repository not found' error as success, for the same
        # reasons as the above error.
        unknown_repository_regex='NAME_UNKNOWN: The repository with name .+ does not exist in the registry '
        if [[ "$result" =~ $unknown_repository_regex ]]; then
          echo "NB The DELETE error was ignored because the repository was already deleted."
          exit 0
        fi
        exit "$exit_code"
      fi
    )
    ;;
  *)
    die "Unknown $ACR_IMAGE_COMMAND command."
    ;;
esac
