<template>
  <Row type="flex" justify="space-around">
    <Col :span="22">
    <PictureCarousel class="picture-carousel"></PictureCarousel>
    <panel shadow v-if="contests.length" class="contest">
      <div slot="title">
        <Button type="text"  class="contest-title" @click="goContest">{{contests[index].title}}</Button>
      </div>
      <Carousel v-model="index" trigger="hover" autoplay :autoplay-speed="6000" class="contest">
        <CarouselItem v-for="(contest, index) of contests" :key="index">
          <div class="contest-content">
            <div class="contest-content-tags">
              <Button type="info" shape="circle" size="small" icon="calendar">
                {{contest.start_time | localtime('YYYY-M-D HH:mm') }}
              </Button>
              <Button type="success" shape="circle" size="small" icon="android-time">
                {{getDuration(contest.start_time, contest.end_time)}}
              </Button>
              <Button type="warning" shape="circle" size="small" icon="trophy">
                {{contest.rule_type}}
              </Button>
            </div>
            <div class="contest-content-description">
              <blockquote v-html="contest.description"></blockquote>
            </div>
          </div>
        </CarouselItem>
      </Carousel>
    </panel>
    <!-- ↓↓↓ 新增 ↓↓↓ -->
    <Alert class="python-banner" show-icon closable>
      <template slot="desc">
        <span class="python-banner-text">
          <Icon type="social-python" class="python-icon"></Icon>
          <b>Python</b> 老刘是世界第一开发
        </span>
      </template>
    </Alert>
    <Announcements class="announcement"></Announcements>
    <RecentRank class="recent-rank"></RecentRank>
    </Col>
  </Row>
</template>

<script>
  import Announcements from './Announcements.vue'
  import PictureCarousel from './PictureCarousel.vue'
  import RecentRank from './RecentRank.vue'
  import api from '@oj/api'
  import time from '@/utils/time'
  import { CONTEST_STATUS } from '@/utils/constants'

  export default {
    name: 'home',
    components: {
      Announcements,
      PictureCarousel,
      RecentRank
    },
    data () {
      return {
        contests: [],
        index: 0
      }
    },
    mounted () {
      let params = {status: CONTEST_STATUS.NOT_START}
      api.getContestList(0, 5, params).then(res => {
        this.contests = res.data.data.results
      })
    },
    methods: {
      getDuration (startTime, endTime) {
        return time.duration(startTime, endTime)
      },
      goContest () {
        this.$router.push({
          name: 'contest-details',
          params: {contestID: this.contests[this.index].id}
        })
      }
    }
  }
</script>

<style lang="less" scoped>
  .picture-carousel {
    margin-bottom: 20px;
  }

  .contest {
    &-title {
      font-style: italic;
      font-size: 21px;
    }
    &-content {
      padding: 0 70px 40px 70px;
      &-description {
        margin-top: 25px;
      }
    }
  }

  .announcement {
    margin-top: 20px;
  }

  .recent-rank {
    margin-top: 20px;
  }
</style>
