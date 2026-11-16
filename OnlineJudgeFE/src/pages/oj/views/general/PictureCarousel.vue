<template>
  <Card :padding="0" :shadow="true" :dis-hover="true" class="picture-carousel-card" v-if="pictures.length">
    <Carousel class="picture-carousel"
              :height="height"
              :autoplay="pictures.length > 1"
              :autoplay-speed="interval"
              :loop="pictures.length > 1"
              :dots="pictures.length > 1"
              :arrow="pictures.length > 1 ? 'hover' : 'never'">
      <CarouselItem v-for="(picture, index) in pictures" :key="index">
        <img class="picture-carousel-image" :src="picture" :alt="'carousel-' + (index + 1)">
      </CarouselItem>
    </Carousel>
  </Card>
</template>

<script>
  // 自动读取 src/assets/picture 下的所有图片，新增/删除图片无需改代码
  const pictureContext = require.context('../../../../assets/picture', false, /\.(png|jpe?g|gif|webp|bmp|svg)$/i)

  export default {
    name: 'PictureCarousel',
    data () {
      return {
        pictures: pictureContext.keys().sort().map(key => pictureContext(key)),
        height: 320,
        interval: 5000
      }
    }
  }
</script>

<style scoped lang="less">
  .picture-carousel-card {
    overflow: hidden;
    border-radius: 4px;
  }

  .picture-carousel-image {
    display: block;
    width: 100%;
    height: 100%;
    object-fit: cover;
  }
</style>
